## pantry-nim

Easy SDK for interacting with [Pantry](https://getpantry.cloud/). **This is not an official project of pantry is just fan made**

#### Examples

(While this examples are synchronous you can use `newAsyncPantryClient` to use async version)

Connecting to your pantry

```nim
let pc = newPantryClient(your-pantry-token)
```

Getting information about pantry

```nim
let pantry = pc.getDetails()

assert pantry.percentFull < 100 # Make sure we are under the limit

# List all your baskets (They are stored has a table)
for basket in pantry.values:
	echo basket.name
```

Information is stored via baskets which is a single JSON object.
Each pantry can have up to 100 baskets (max size is 1.44mb each)

```nim
# You can use the basket object to easily interact with the basket
let basket = pc.createBasket("test", %* {
	"foo": "bar"
})

assert basket.getData()["foo"] == %"bar"

let newData = basket.update(%* {
	"foo": "notBar"
})

assert newData["foo"] == %"notBar"

delete basket
```

