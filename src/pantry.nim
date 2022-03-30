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

const 
  baseURL = "https://getpantry.cloud/apiv1/pantry"
  userAgent = "pantry-nim (0.1.0) [https://github.com/ire4ever1190/pantry-nim]"

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

proc newPantryClient*(id: string, strat: RetryStrategy): PantryClient = 
  ## Creates a Pantry client for sync use
  result = newBaseClient[HttpClient](id, strat)

proc newAsyncPantryClient*(id: string, strat: RetryStrategy): AsyncPantryClient =
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
      when compiles(await sleepAsync 1):
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
    echo resp.code
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


proc update*(pc: PantryClient | AsyncPantryClient, basket: string, newData: JsonNode): Future[JsonNode] {.multisync.} =
  ## Given a basket name, this will update the existing contents and return the contents of the newly updated basket. 
  ## This operation performs a deep merge and will overwrite the values of any existing keys, or append values to nested objects or arrays.
  ## Returns the updated data.
  checkJSON newData
  result = pc.request("/basket/" & basket, HttpPut, $newData)
    .await()
    .parseJson()

proc get*(pc: PantryClient | AsyncPantryClient, basket: string): Future[JsonNode] {.multisync.} =
  ## Given a basket name, return the full contents of the basket.
  result = pc.request("/basket/" & basket, HttpGet)
    .await()
    .parseJson()

proc delete*(pc: PantryClient | AsyncPantryClient, basket: string) {.multisync.} =
  ## Delete the entire basket. Warning, this action cannot be undone.
  discard await pc.request("/basket/" & basket, HttpDelete)

export tables
export json
