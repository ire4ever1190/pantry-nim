import std/unittest
import std/times
import std/json
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

test "Objects":
  var order = Order(time: 123456789, items: @[
    Item(name: "Soap", price:  0.49),
    Item(name: "Crisps", price: 0.70)
  ])
  pc.create("order", order)
