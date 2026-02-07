{.define: ssl.}

import std/[
  httpclient,
  asyncdispatch,
  httpcore,
  strutils,
  json,
  jsonutils,
  times,
  strformat,
  os,
  options,
  typetraits,
  tables,
  uri
]

include pantry/common

##
## This library is a small wrapper around `Pantry <https://getpantry.cloud/>`_ which is a simple json storage service.
##
## Key information for when following this guide
##
## Common terms
## * **Basket**: A JSON object that you store data in
## * **Pantry**: A collection of baskets
##
## Limitations
## * Each bucket can only store 1.44mb max
## * Each pantry can only store 100 buckets max
## * Each pantry can't be over 100mb in size
## * Inactive buckets are deleted after 30 days
##
## Create a pantry and then you can follow along with the rest of the docs.
##
## Creating the client
## ===================
##
## The client is made with either newPantryClient_ or newAsyncPantryClient_ which provide sync and async apis respectively.
## These clients can be passed a RetryStrategy_ which handles how they handle a timeout

runnableExamples "-r:off":
  import std/asyncdispatch
  let
    # Create normal sync client that will error on 'too many requests'
    client = newPantryClient("pantry-id")
    # Create async client that will sleep and then retry on 'too many requests'
    aClient = newAsyncPantryClient("pantry-id", strat = Retry)

  try:
    for i in 1..100:
      echo client.getDetails()
  except TooManyPantryRequests:
    echo "Slow down!"

  proc spamDetails() {.async.} =
    # This will not error out since it will just sleep if
    # making too many requests
    for i in 1..100:
      echo await aClient.getDetails()

  waitFor spamDetails()
  close client
  close aClient
# Note: data is pronounced 'data' in the following examples

##
## Adding Data
## ===========
##
## Buckets can have their data set via the create_ proc
##
## .. Warning:: This overwrites any data currently present in the bucket

runnableExamples "-r:off":
  let client = newPantryClient("pantry-id")

  var data = %* {
    "lenFilms": 145,
    "genres": ["Comedy", "Horror"]
  }
  # Set the "films" bucket to contain the data
  client.create("films", data)

  # Reset the bucket so it only contains number of films
  client.create("films", %* {"lenFilms": 0})

## Getting Data
## ============
##
## Once a bucket has data you can then retrive it at a later date using get_

runnableExamples "-r:off":
  let client = newPantryClient("pantry-id")

  # See example in adding data to see what this is
  let films = client.get("films")

  assert films["lenFilms"].getInt() == 0
  assert "genres" notin films

## Updating Data
## =============
##
## Buckets can have their contents updated using update_ which means
## * Values of existing keys are overwritten
## * Values of new keys are added
## * Arrays are merged together

runnableExamples "-r:off":
  let client = newPantryClient("pantry-id")

  # Lets add back in the genres and bump up the number of films
  discard client.update("films", %* {
    "genres": ["Comedy", "Horror"],
    "lenFilms": 99
  })

  type
    FilmData = object
      lenFilms: int
      genres: seq[string]

  # Now lets add in another genre
  let newData = client.update("films", %* {
    "genres": ["Sci-Fi"]
  }).to(FilmData)


  assert newData.lenFilms == 99
  assert newData.genres == ["Comedy", "Horror", "Sci-Fi"]

## Removing Data
## =============
##
## Very simple operation, deletes the bucket
##
## .. Danger:: Operation cannot be undone, be careful

runnableExamples "-r:off":
  let client = newPantryClient("pantry-id")

  client.delete("films")

const
  baseURL = "https://getpantry.cloud/apiv1/".parseUri()
  userAgent = "pantry-nim (0.4.2) [https://github.com/ire4ever1190/pantry-nim]"


## Using objects instead of JsonNode
## =================================
##
## It is possible to use objects for sending and receiving objects instead of having to work with JsonNode.
## This can be done by just passing an object instead of json like so

runnableExamples "-r:off":
  type
    FilmData = object
      lenFilms: int
      genres: seq[string]

  let
    client = newPantryClient("pantry-id")
    data = FilmData(lenFilms: 9, genres: @["Comedy", "Action", "Adventure"])

  # API is the same has before, except you need to specify type when getting
  client.create("films", data)
  assert client.get("films", FilmData) == data

## This also allows you to avoid exceptions and get Option[T] return types instead

runnableExamples "-r:off":
  import std/options
  let client = newPantryClient("pantry-id")

  # if 'doesntExist' doesn't exist in the pantry then BasketDoesntExist exception
  # would be thrown
  try:
    discard client.get("doesntExist")
  except BasketDoesntExist:
    discard

  # Doesn't need to be JsonNode, any type works
  let data = client.get("doesntExist", Option[JsonNode])
  # No exception will be raised if it doesn't exist, but it will be `none`
  if data.isSome:
    # Do stuff if the basket exists
    discard
  else:
    # Do stuff if the basket doesn't exist
    discard

#
# End of documentation, start of code
#

proc fromJsonHook(a: var Table[string, Basket], baskets: JsonNode, opt = JOptions()) =
  ## Used for converting list of baskets to a table
  for basket in baskets:
    let basketName = basket["name"].getStr()
    a[basketName] = Basket(
      name: basketName,
      ttl: basket["ttl"].getInt()
    )

proc newBaseClient[T: Clients](id: string, strat: RetryStrategy): BasePantryClient[T] =
  result.id = id.strip()
  result.strat = strat
  when T is AsyncHttpClient:
    result.client = newAsyncHttpClient(userAgent = userAgent)
  else:
    result.client = newHttpClient(userAgent = userAgent)

proc newPantryClient*(id: string, strat: RetryStrategy = Exception): PantryClient =
  ## Creates a Pantry client for sync use
  result = newBaseClient[HttpClient](id, strat)

proc newAsyncPantryClient*(id: string, strat: RetryStrategy = Exception): AsyncPantryClient =
  ## Creates a Pantry client for async use
  result = newBaseClient[AsyncHttpClient](id, strat)

proc close*(pc: BasePantryClient) =
  ## Closes the pantry client. Closing is automatically done
  ## so you shouldn't need to close this unless you want to close earlier than the GC
  pc.client.close()

proc pantryUrl(pc: BasePantryClient): URI =
  ## Returns a URI that points to the clients pantry
  baseURL / "pantry" / pc.id

template checkJSON(json: JsonNode) =
  ## Checks that the json is an object (pantry requires this)
  assert json.kind == JObject, "JSON must be a single object"

proc request(pc: PantryClient | AsyncPantryClient, path: URI,
             meth: HttpMethod, body: string = "", retry = 3): Future[string] {.gcsafe, multisync.} =
  ## Make a request to pantry
  let resp = await pc.client.request(
    path,
    meth, body = body,
    headers = newHttpHeaders {
      "Content-Type": "application/json"
    }
  )
  let msg = await resp.body
  case resp.code.int
  of 200..299:
    result = msg
  of 400:
    # Pantry stuff both 404 and 401 errors into this so we need to parse them out.
    # This is a bit of a hacky way to do it, maybe ask pantry team why 400 is used?
    if "does not exist" in msg:
      raise (ref BasketDoesntExist)(msg: msg)
    elif "not found" in msg:
      raise (ref InvalidPantryID)(msg: msg)

  of 429: # Handle too many requests
    # Sometimes pantry doesn't give us a timeout, just sleep for 10
    let sleepTime = block:
      let parsedSleep = resp.headers["retry-after"].parseInt()
      if parsedSleep == 0: 10 else: parsedSleep
    # Check how to handle the error
    if pc.strat == Exception or retry == 0:
      raise (ref TooManyPantryRequests)(
        msg: fmt"Too many requests, please wait {sleepTime} seconds",
        retryAfter: sleepTime
      )
    elif pc.strat in {Sleep, Retry}:
      when pc is AsyncPantryClient:
        await sleepAsync sleepTime * 1000
      else:
        sleep sleepTime * 1000

      if pc.strat == Retry and retry > 0:
        result = await pc.request(path, meth, body, retry = retry - 1)

  else:
    raise (ref PantryError)(msg: msg)

proc updateDetails*(pc: PantryClient | AsyncPantryClient, name, description: string): Future[PantryDetails] {.multisync.} =
  ## Updates a pantry's details
  result = pc.request(pc.pantryUrl(), HttpPut, $ %* {
      "name": name,
      "description": description
    })
    .await()
    .parseJson()
    .jsonTo(PantryDetails)

proc getDetails*(pc: PantryClient | AsyncPantryClient): Future[PantryDetails] {.multisync.} =
  ## Returns details for current pantry
  result = pc.request(pc.pantryUrl(), HttpGet)
    .await()
    .parseJson()
    .jsonTo(PantryDetails)

proc create*(pc: PantryClient | AsyncPantryClient, basket: string,
                   data: JsonNode) {.multisync.} =
  ## Creates a basket in a pantry. If the basket already exists then it overwrites it
  checkJSON data
  discard await pc.request(pc.pantryUrl / "basket" / basket, HttpPost, $data)

proc update*(pc: PantryClient | AsyncPantryClient, basket: string, newData: JsonNode): Future[JsonNode] {.multisync.} =
  ## Given a basket name, this will update the existing contents and return the contents of the newly updated basket.
  ## This operation performs a deep merge and will overwrite the values of any existing keys, or append values to nested objects or arrays.
  ## Returns the updated data.
  checkJSON newData
  result = pc.request(pc.pantryUrl / "basket" / basket, HttpPut, $newData)
    .await()
    .parseJson()

proc get*(pc: PantryClient | AsyncPantryClient, basket: string): Future[JsonNode] {.multisync.} =
  ## Given a basket name, return the full contents of the basket.
  result = pc.request(pc.pantryUrl / "basket" / basket, HttpGet)
    .await()
    .parseJson()

proc delete*(pc: PantryClient | AsyncPantryClient, basket: string) {.multisync.} =
  ## Delete the entire basket. Warning, this action cannot be undone.
  discard await pc.request(pc.pantryUrl / "basket" / basket, HttpDelete)

#
# Now we have versions of get/create/update that are generic and take objects
#

template optionExcept(body: untyped): untyped =
  # If T is Option[T] then if an exception occurs it will just return `none` instead
  # of throwing an exception
  when T is Option:
    try:
      # template await(value: untyped): untyped =
        # value
      # bind await
      body
    except BasketDoesntExist:
      discard
  else:
    body


template wrapData(x): JsonNode =
  ## Since pantry doesn't allow non objects at top level we need to wrap the type
  when T isnot object and T isnot ref object:
    %*{"item": x}
  else:
    %*x

template unwrapData(x: JsonNode): untyped =
  when T isnot object and T isnot ref object:
    x["item"].to(T)
  else:
    x.to(T)

proc get*[T](pc: PantryClient | AsyncPantryClient, basket: string, kind: typedesc[T]): Future[T] {.multisync.} =
  ## Like create_ except it parses the JSON and returns an object
  optionExcept:
    result = unwrapData await pc.get(basket)

proc getPublicId*(pc: PantryClient | AsyncPantryClient, basket: string): Future[string] {.multisync.} =
  ## Returns the public ID for a basket. This can be shared with other users without needing authorization via the URL format
  ## `https://getpantry.cloud/apiv1/public/PUBLIC_BASKET_ID`
  result = pc.request(pc.pantryUrl / "basket" / basket / "public", HttpGet)
    .await()

proc getPublic*(pc: PantryClient | AsyncPantryClient, basket: string): Future[JsonNode] {.multisync.} =
  ## Like [get] but works on public baskets
  result = pc.request(baseURL / "public" / basket, HttpGet)
    .await()
    .parseJson()

proc getPublic*[T](pc: PantryClient | AsyncPantryClient, basket: string, kind: typedesc[T]): Future[T] {.multisync.} =
  ## Like [getPublic] except it parses the JSON and returns an object
  optionExcept:
    result = unwrapData await pc.getPublic(basket)

proc create*[T: not JsonNode](pc: PantryClient | AsyncPantryClient, basket: string, data: T) {.multisync.} =
  ## like create_ except it works with normal objects
  optionExcept:
    await pc.create(basket, wrapData(data))

proc update*[T: not JsonNode](pc: PantryClient | AsyncPantryClient, basket: string, newData: T): Future[T] {.multisync.} =
  ## Like update_ except data is an object
  optionExcept:
    result = unwrapData await pc.update(basket, wrapData(newData))


export tables
export json
