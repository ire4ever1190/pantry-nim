import std/[
  httpclient,
  asyncdispatch,
  httpcore,
  strutils,
  json,
  jsonutils
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

proc newPantryClient*(id: string): PantryClient = 
  ## Creates a Pantry client for sync use
  PantryClient(
    id: id.strip(),
    client: newHttpClient(userAgent = userAgent)
  )

proc newAsyncPantryClient*(id: string): AsyncPantryClient =
  ## Creates a Pantry client for async use
  AsyncPantryClient(
    id: id,
    client: newAsyncHttpClient(userAgent = userAgent)
  )

func createURL(pc: PantryClient | AsyncPantryClient, path: string): string =
  ## Adds pantry id and path to base path and returns new path
  result = baseURL
  result &= "/"
  result &= pc.id
  result &= path

proc request(pc: PantryClient | AsyncPantryClient, path: string, 
             meth: HttpMethod, body: string = ""): Future[string] {.multisync.} =
  ## Make a request to pantry
  let resp = await pc.client.request(
    pc.createURL(path),
    meth, body = body,
    headers = newHttpHeaders {
      "Content-Type": "application/json"
    }
  )
  if resp.code.is2xx:
    result = await resp.body
  else:
    raise (ref PantryError)(msg: await resp.body)

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
  discard await pc.request("/basket/" & basket, HttpPost, $data)


proc update*(pc: PantryClient | AsyncPantryClient, basket: string, newData: JsonNode): Future[JsonNode] {.multisync.} =
  ## Given a basket name, this will update the existing contents and return the contents of the newly updated basket. 
  ## This operation performs a deep merge and will overwrite the values of any existing keys, or append values to nested objects or arrays.
  ## Returns the updated data.
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
