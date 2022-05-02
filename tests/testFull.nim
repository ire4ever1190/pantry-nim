import std/unittest
import std/times
import std/json
import std/options
import pantry

# This is E2E tests. Make sure to include a file called token containing your pantry test ID in the root of the repo

let pc = newPantryClient("token".readFile(), Retry)

let time = now().format("yyyy-MM-dd hh:mm:ss")

suite "Pantry":
  test "Update details":
    check pc.updateDetails("Test", time).description == time

  test "Get details":
    let details = pc.getDetails()
    check:
      details.description == time
      details.name == "Test"

suite "Basket":
  test "Create":
    pc.create("demo", %* {
      "currTime": time
    })

  test "Update":
    check pc.update("demo", %* {
      "foo": "bar"
    })["foo"].getStr() == "bar"

  test "Get contents":
    let data = pc.get("demo")
    check:
      data["currTime"].getStr() == time
      data["foo"].getStr() == "bar"

  test "Delete":
    pc.delete("demo")
    check not pc.getDetails().baskets.hasKey("demo")

type 
  Item = object
    name: string
    price: float
    
  Order = object
    time: int
    items: seq[Item]

suite "Objects":
  let order = Order(time: 123456789, items: @[
    Item(name: "Soap", price:  0.49),
    Item(name: "Crisps", price: 0.70)
  ])
  test "Creating":
    pc.create("order", order)

  test "Getting":
    check pc.get("order", Order) == order

  test "Updating":
    let newOrder = Order(
      time: order.time,
      items: @[Item(name: "PC", price: 800.0)]
    )
    check pc.update("order", newOrder) == Order(
      time: order.time,
      items: order.items & Item(name: "PC", price: 800.0)
    )

suite "Invalid inputs":
  test "Wrong pantry ID":
    let pc = newPantryClient("invalid-id")
    
    expect InvalidPantryID:
      pc.create("test", %*{"foo": "bar"}) 

  test "Wrong pantry with wrong pantry ID":
    let pc = newPantryClient("invalid-id")

    expect InvalidPantryID:
      discard pc.get("test")

  test "Not found basket name":
    expect BasketDoesntExist:
      discard pc.get("IDontExist")

  test "Option return instead of exception":
    check pc.get("IDontExist", Option[JsonNode]).isNone()
    
  test "Not passing a json object":
    expect AssertionDefect:
      pc.create("array", %*[1, 2, 3])
