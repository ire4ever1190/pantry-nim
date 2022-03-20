import std/unittest
import std/strutils
import std/times
import std/json
import pantry

# This is E2E tests. Make sure to include a file called token containing your pantry test ID in the root of the repo

let pc = newPantryClient("token".readFile())

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
  var basket: Basket
  test "Create":
    basket = pc.createBasket("demo", %* {
      "currTime": time
    })
    basket = pc.getBasket("demo")

  test "Update":
    check basket.update(%* {
      "foo": "bar"
    })["foo"].getStr() == "bar"

  test "Get contents":
    let data = basket.getData()
    check:
      data["currTime"].getStr() == time
      data["foo"].getStr() == "bar"

  test "Delete":
    delete basket
    check not pc.getDetails().baskets.hasKey("demo")
  
