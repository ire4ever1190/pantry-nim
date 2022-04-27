import std/[
  httpclient,
  asyncdispatch,
  httpcore,
  strutils,
  json,
  jsonutils,
  times,
  strformat,
  os
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
  baseURL = "https://getpantry.cloud/apiv1/pantry"
  userAgent = "pantry-nim (0.2.0) [https://github.com/ire4ever1190/pantry-nim]"


## Using objects instead of JsonNode
## =================================
##
## It is possible to use objects for sending and receiving objects instead of having to work with 

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

func createURL(pc: PantryClient | AsyncPantryClient, path: string): string =
  ## Adds pantry id and path to base path and returns new path
  result = baseURL
  result &= "/"
  result &= pc.id
  result &= path

template checkJSON(json: JsonNode) = 
  ## Checks that the json is an object (pantry requires this)
  assert json.kind == JObject, "JSON must be a single object"

proc request(pc: PantryClient | AsyncPantryClient, path: string, 
             meth: HttpMethod, body: string = "", retry = 3): Future[string] {.multisync.} =
  ## Make a request to pantry
  let resp = await pc.client.request(
    pc.createURL(path),
    meth, body = body,
    headers = newHttpHeaders {
      "Content-Type": "application/json"
    }
  )
  let msg = await resp.body
  case resp.code.int
  of 200..299:
    result = msg
  of 429: # Handle too many requests
    let time =  msg[43..75].parse("ddd MMM dd yyyy HH:mm:ss 'GMT'ZZZ") # Get time to make next request
    let sleepTime = (time - now())
    if pc.strat in {Sleep, Retry}:
      when pc is AsyncPantryClient:
        await sleepAsync int(sleepTime.inMilliseconds)
      else:
        sleep int(sleepTime.inMilliseconds)
        
      if pc.strat == Retry and retry > 0:
        result = await pc.request(path, meth, body, retry = retry - 1)
      
    elif pc.strat == Exception or retry == 0:
      raise (ref TooManyPantryRequests)(
        msg: fmt"Too many requests, please wait {sleepTime.inSeconds} seconds"
      )
  else:
    raise (ref PantryError)(msg: msg)

proc updateDetails*(pc: PantryClient | AsyncPantryClient, name, description: string): Future[PantryDetails] {.multisync.} =
  ## Updates a pantry's details
  result = pc.request("", HttpPut, $ %* {
      "name": name,
      "description": description
    })
    .await()
    .parseJson()
    .jsonTo(PantryDetails)

proc getDetails*(pc: PantryClient | AsyncPantryClient): Future[PantryDetails] {.multisync.} =
  ## Returns details for current pantry
  result = pc.request("", HttpGet)
    .await()
    .parseJson()
    .jsonTo(PantryDetails)
  
proc create*(pc: PantryClient | AsyncPantryClient, basket: string,
                   data: JsonNode) {.multisync.} =
  ## Creates a basket in a pantry. If the basket already exists then it overwrites it
  checkJSON data
  discard await pc.request("/basket/" & basket, HttpPost, $data)

proc create*[T: not JsonNode](pc: PantryClient | AsyncPantryClient, basket: string, data: T) {.multisync.} =
  ## like `create(AsyncPantryClient, string, JsonNode)`_ except it works with normal objects
  await pc.create(basket, %*data)

proc update*(pc: PantryClient | AsyncPantryClient, basket: string, newData: JsonNode): Future[JsonNode] {.multisync.} =
  ## Given a basket name, this will update the existing contents and return the contents of the newly updated basket. 
  ## This operation performs a deep merge and will overwrite the values of any existing keys, or append values to nested objects or arrays.
  ## Returns the updated data.
  checkJSON newData
  result = pc.request("/basket/" & basket, HttpPut, $newData)
    .await()
    .parseJson()

proc update*[T: not JsonNode](pc: PantryClient | AsyncPantryClient, basket: string, newData: T): Future[T] {.multisync.} =
  ## Like `update(AsyncPantryClient, string, JsonNode)`_ except data is an object
  pc.update(basket, %*newData).await().to(T)

proc get*(pc: PantryClient | AsyncPantryClient, basket: string): Future[JsonNode] {.multisync.} =
  ## Given a basket name, return the full contents of the basket.
  result = pc.request("/basket/" & basket, HttpGet)
    .await()
    .parseJson()

proc get*[T](pc: PantryClient | AsyncPantryClient, basket: string, kind: typedesc[T]): Future[T] {.multisync.} =
  ## Like `create(AsyncPantryClient, string, JsonNode)`_ except it parses the JSON and returns an object
  result = pc.get(basket).await().to(T)


proc delete*(pc: PantryClient | AsyncPantryClient, basket: string) {.multisync.} =
  ## Delete the entire basket. Warning, this action cannot be undone.
  discard await pc.request("/basket/" & basket, HttpDelete)

export tables
export json
