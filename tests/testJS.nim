discard """
targets: "js"
"""

import std/[unittest, asyncjs, options]
import pantry


# Tests are shamelessly taken from testFull.nim

const token = staticRead("../token")
let pc = newAsyncPantryClient(token, Retry)

let time = "2000-01-01 11:11:11"


type 
  Item = object
    name: string
    price: float
    
  Order = object
    time: int
    items: seq[Item]

proc main() {.async.} =
  # Update details
  doAssert pc.updateDetails("Test", time).await().description == time

  # Get details 
  block:
    let details = await pc.getDetails()
    doAssert details.description == time
    doAssert details.name == "Test"

  # Create basket
  await pc.create("demo", %* {
    "currTime": time
  })

  # Update basket
  doAssert pc.update("demo", %* {
    "foo": "bar"
  }).await()["foo"].getStr() == "bar"

  # Get contents
  block:
    let data = await pc.get("demo")
    doAssert data["currTime"].getStr() == time
    doAssert data["foo"].getStr() == "bar"

  # Delete basket
  await pc.delete("demo")
  doAssert not pc.getDetails().await().baskets.hasKey("demo")

  # Tests involving object parsing

  let order = Order(time: 123456789, items: @[
    Item(name: "Soap", price:  0.49),
    Item(name: "Crisps", price: 0.70)
  ])
  await pc.create("order", order)

  doAssert pc.get("order", Order).await() == order

  block:
    let newOrder = Order(
      time: order.time,
      items: @[Item(name: "PC", price: 800.0)]
    )
    doAssert pc.update("order", newOrder).await() == Order(
      time: order.time,
      items: order.items & Item(name: "PC", price: 800.0)
    )

  # Test we handle invalid inputs
  block:
    # Wrong key
    let pc = newAsyncPantryClient("invalid-id")
    
    doAssertRaises InvalidPantryID:
      await pc.create("test", %*{"foo": "bar"}) 

  block:
    # Wrong key and pantry
    let pc = newAsyncPantryClient("invalid-id")

    doAssertRaises InvalidPantryID:
      discard await pc.get("test")


  doAssertRaises BasketDoesntExist:
    discard await pc.get("IDontExist")

  doAssert pc.get("IDontExist", Option[JsonNode]).await().isNone()
    
  doAssertRaises AssertionDefect:
    await pc.create("array", %*[1, 2, 3])

  echo "Everything passed"
discard main()
