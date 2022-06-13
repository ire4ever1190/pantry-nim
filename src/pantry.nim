from httpcore import HttpMethod
import std/[
  strutils,
  json,
  jsonutils,
  times,
  strformat,
  options,
  typetraits,
  tables,
  sugar
]
import strutils

include pantry/common
when not usingJS:
  import std/[
    asyncdispatch,
    httpclient,
    os
  ]
else:
  import std/[
    asyncjs,
    jsffi,
    jsfetch,
    jsheaders,
    dom
  ]
  import macros
  # Small shim to make multisync procs only async on JS backend
  macro multisync(prc: untyped) = 
    result = prc
    # Also remove the first parameter to stop generic binding issues
    if result.params[1][0].eqIdent("pc"):
      result.params[1][1] = ident"AsyncPantryClient"
    result.addPragma(ident"async")
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
##
## .. Info:: only newAsyncPantryClient works when using JS backend
##
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

proc fromJsonHook(a: var Table[string, Basket], baskets: JsonNode) =
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
  when not usingJS:
    when T is AsyncHttpClient:
      result.client = newAsyncHttpClient(userAgent = userAgent)
    elif T is HttpClient:
      result.client = newHttpClient(userAgent = userAgent)

when not usingJS:
  proc newPantryClient*(id: string, strat: RetryStrategy = Exception): PantryClient = 
    ## Creates a Pantry client for sync use
    result = newBaseClient[HttpClient](id, strat)

proc newAsyncPantryClient*(id: string, strat: RetryStrategy = Exception): AsyncPantryClient =
  ## Creates a Pantry client for async use
  when not usingJS:
    result = newBaseClient[AsyncHttpClient](id, strat)
  else:
    result = newBaseClient[void](id, strat)
    
func createURL(pc: PantryClients, path: string): string =
  ## Adds pantry id and path to base path and returns new path
  result = baseURL
  result &= "/"
  result &= pc.id
  result &= path

when usingJS:
  # Helpers for making JS behave like HttpClient
  template code(resp: Response): cint =
    resp.status

  template contentType(resp: Response): string =
    $resp.headers["Content-Type"]
    


template checkJSON(json: JsonNode) = 
  ## Checks that the json is an object (pantry requires this)
  assert json.kind == JObject, "JSON must be a single object"
  
proc request(pc: PantryClient | AsyncPantryClient, path: string, 
             meth: HttpMethod, body: string = "", retry = 3): Future[JsonNode] {.multisync.} =
  ## Make a request to pantry
  let url = pc.createURL(path)
  when not usingJS:
    # Use normal HTTP client
    let resp = await pc.client.request(
      url,
      meth, body = body,
      headers = newHttpHeaders {
        "Content-Type": "application/json"
      }
    )
    let msg = await resp.body
  else:
    # Set up fetch request
    var headers = newHeaders()
    headers["Content-Type"] = "application/json"
    let options = newFetchOptions(
      meth,
      body,
      fmNoCors,
      fcOmit,
      fchDefault,
      frpNoReferrer,
      true,
      referrer = "http://example.com",
      headers = headers
    )
    let 
      resp = await fetch(url.cstring, options)
      msg = $(await resp.text)

  case resp.code.int
  of 200..299:
    if resp.contentType.startsWith("application/json"):
      result = msg.parseJson()
      
  of 400:
    # Pantry stuff both 404 and 401 errors into this so we need to parse them out.
    # This is a bit of a hacky way to do it, maybe ask pantry team why 400 is used?
    if "does not exist" in msg:
      raise (ref BasketDoesntExist)(msg: msg)
    elif "not found" in msg:
      raise (ref InvalidPantryID)(msg: msg)
    
  of 429: # Handle too many requests
    let time =  msg[43..75].parse("ddd MMM dd yyyy HH:mm:ss 'GMT'ZZZ") # Get time to make next request
    let sleepTime = time - now()
    # Check how to handle the error
    if pc.strat == Exception or retry == 0:
      raise (ref TooManyPantryRequests)(
        msg: fmt"Too many requests, please wait {sleepTime.inSeconds} seconds"
      )
    elif pc.strat in {Sleep, Retry}:
      when not usingJS:
        when pc is AsyncPantryClient:
          await sleepAsync int(sleepTime.inMilliseconds)
        else:
          sleep int(sleepTime.inMilliseconds)
          
        if pc.strat == Retry and retry > 0:
          result = await pc.request(path, meth, body, retry = retry - 1)
      else:
        # Timer is only way to sleep in JS, makes a timer which then returns a promise that
        # will contain the value of the new attempt
        result = newPromise do (res: proc (x: JsonNode)):
          discard setTimeout(proc () =
            echo "retrying"
            if pc.strat == Retry and retry > 0:
              discard pc.request(path, meth, retry = retry - 1).then(res)
          , sleepTime)
      
  else:
    raise (ref PantryError)(msg: msg)

proc updateDetails*(pc: PantryClient | AsyncPantryClient, name, description: string): Future[PantryDetails] {.multisync.} =
  ## Updates a pantry's details
  result = pc.request("", HttpPut, $ %* {
      "name": name,
      "description": description
    })
    .await()
    .jsonTo(PantryDetails)

proc getDetails*(pc: PantryClient | AsyncPantryClient): Future[PantryDetails] {.multisync.} =
  ## Returns details for current pantry
  result = pc.request("", HttpGet)
    .await()
    .jsonTo(PantryDetails)
  
proc create*(pc: PantryClient | AsyncPantryClient, basket: string,
                   data: JsonNode) {.multisync.} =
  ## Creates a basket in a pantry. If the basket already exists then it overwrites it
  checkJSON data
  discard await pc.request("/basket/" & basket, HttpPost, $data)

proc update*(pc: PantryClient | AsyncPantryClient, basket: string, newData: JsonNode): Future[JsonNode] {.multisync.} =
  ## Given a basket name, this will update the existing contents and return the contents of the newly updated basket. 
  ## This operation performs a deep merge and will overwrite the values of any existing keys, or append values to nested objects or arrays.
  ## Returns the updated data.
  checkJSON newData
  result = await pc.request("/basket/" & basket, HttpPut, $newData)

proc get*(pc: PantryClient | AsyncPantryClient, basket: string): Future[JsonNode] {.multisync.} =
  ## Given a basket name, return the full contents of the basket.
  result = await pc.request("/basket/" & basket, HttpGet)

proc delete*(pc: PantryClient | AsyncPantryClient, basket: string) {.multisync.} =
  ## Delete the entire basket. Warning, this action cannot be undone.
  discard await pc.request("/basket/" & basket, HttpDelete)

# 
# Now we have versions of get/create/update that are generic and take objects
#

template optionExcept(body: untyped): untyped =
  # If T is Option[T] then if an exception occurs it will just return `none` instead 
  # of throwing an exception
  when T is Option:
    try:
      body
    except BasketDoesntExist:
      # Result is none by default so we don't need to do
      # anything
      discard
  else:
    body

proc get*[T](pc: PantryClient | AsyncPantryClient, basket: string, kind: typedesc[T]): Future[T] {.multisync.} =
  ## Like create_ except it parses the JSON and returns an object
  optionExcept:
    result = to(await pc.get(basket), kind)

proc create*[T: not JsonNode](pc: PantryClient | AsyncPantryClient, basket: string, data: T) {.multisync.} =
  ## like create_ except it works with normal objects
  optionExcept:
    await pc.create(basket, %*data)
  
proc update*[T: not JsonNode](pc: PantryClient | AsyncPantryClient, basket: string, newData: T): Future[T] {.multisync.} =
  ## Like update_ except data is an object
  optionExcept:
    result = to(await pc.update(basket, %*newData), T)


export tables
export json
