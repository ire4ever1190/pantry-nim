import std/[
  httpclient,
  asyncdispatch,
  httpcore,
  strutils,
  with,
  json
]

include pantry/common

const 
  baseURL = "https://getpantry.cloud/apiv1/pantry"
  userAgent = "pantry-nim (0.1.0) [https://github.com/ire4ever1190/pantry-nim]"

proc newPantryClient*(id: string): PantryClient = 
  ## Creates a Pantry client for sync use
  PantryClient(
    id: id.strip(),
    client: newHttpClient(userAgent = userAgent)
  )

template isAsync(pc: PantryClient | AsyncPantryClient): static[bool] =
  typeof(pc) is AsyncPantryClient

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

proc to[T: PantryClients](resp: JsonNode, t: typedesc[PantryDetails], pc: T): PantryDetails[T] = 
  ## Converts json to pantry details
  ## Needs to be done manually so that basket can have client passed to it
  with result:
    name = resp["name"].str
    description = resp["description"].getStr()
    errors = resp["errors"].to(seq[string])
    notifications = resp["notifications"].getBool()
    percentFull = resp["percentFull"].getInt()
    
  for basket in resp["baskets"]:
    let basketName = basket["name"].getStr()
    result.baskets[basketName] = BaseBasket[T](
      client: pc,
      name: basketName,
      ttl: basket["ttl"].getInt()
    )

proc updateDetails*(pc: PantryClient | AsyncPantryClient, name, description: string): Future[PantryDetails[typeof(pc)]] {.multisync.} =
  ## Updates a pantry's details
  result = pc.request("", HttpPut, $ %* {
      "name": name,
      "description": description
    })
    .await()
    .parseJson()
    .to(PantryDetails, pc)

proc getDetails*(pc: PantryClient | AsyncPantryClient): Future[PantryDetails[typeof(pc)]] {.multisync.} =
  ## Returns details for current pantry
  result = pc.request("", HttpGet)
    .await()
    .parseJson()
    .to(PantryDetails, pc)

proc getBasket*(pc: PantryClient | AsyncPantryClient, basket: string, ttl = 0): BaseBasket[typeof(pc)] =
  ## Returns a basket object that can be used to easily interact with a basket (Doesn't return the basket data)
  # This is more of a dummy proc then anything
  result = BaseBasket[typeof(pc)](
    ttl: ttl,
    client: pc,
    name: basket
  )

  
proc createBasket*(pc: PantryClient | AsyncPantryClient, basket: string,
                   data: JsonNode): Future[BaseBasket[typeof(pc)]] {.multisync.} =
  ## Creates a basket in a pantry. If the basket already exists then it overwrites it
  discard await pc.request("/basket/" & basket, HttpPost, $data)
  result = pc.getBasket(basket) # Should TTL be 30 days?


proc replace*(basket: Basket | AsyncBasket, newData: JsonNode) {.multisync.} =
  ## Replaces existing info in a basket with new info
  discard await basket.client.createBasket(basket.name, newData)

proc updateBasket*(pc: PantryClient | AsyncPantryClient, basket: string, newData: JsonNode): Future[JsonNode] {.multisync.} =
  ## Given a basket name, this will update the existing contents and return the contents of the newly updated basket. 
  ## This operation performs a deep merge and will overwrite the values of any existing keys, or append values to nested objects or arrays.
  result = pc.request("/basket/" & basket, HttpPut, $newData)
    .await()
    .parseJson()

proc update*(basket: Basket | AsyncBasket, newData: JsonNode): Future[JsonNode] {.multisync.} =
  ## See updateBucket_
  result = await basket.client.updateBasket(basket.name, newData)

proc getData*(pc: PantryClient | AsyncPantryClient, basket: string): Future[JsonNode] {.multisync.} =
  ## Given a basket name, return the full contents of the basket.
  result = pc.request("/basket/" & basket, HttpGet)
    .await()
    .parseJson()

proc getData*(basket: Basket | AsyncBasket): Future[JsonNode] {.multisync.} =
  ## See getData_
  result = await basket.client.getData(basket.name)

proc deleteBasket*(pc: PantryClient | AsyncPantryClient, basket: string) {.multisync.} =
  ## Delete the entire basket. Warning, this action cannot be undone.
  discard await pc.request("/basket/" & basket, HttpDelete)

proc delete*(basket: Basket | AsyncBasket) {.multisync.} =
  ## see deleteBasket_
  await basket.client.deleteBasket(basket.name)

export tables
