## pantry-nim

Easy SDK for interacting with [Pantry](https://getpantry.cloud/). 

**This is not an official project of pantry and is just fan made**

[Docs here](https://tempdocs.netlify.app/pantry/stable)

#### Installation

`nimble install pantry`

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
Each pantry can have up to 100 baskets (max size is 1.44mb each).
Baskets can be interacted with the following operations

	- `create`: Sets the data of the basket, overwrites existing information
	- `update`: Updates the information currently in a basket
	- `get`: Gets the information stored inside a basket
	- `delete`: Deletes the basket

```nim
pc.create("test", %* {
  "foo": "bar"
})

assert pc.get("test")["foo"] == %"bar"

let newData = pc.update("test", %* {
  "foo": "notBar"
})

assert newData["foo"] == %"notBar"

pc.delete("foo")
```

Objects can be used instead of `JsonNode` for `create`, `get`, and `update`

```nim
type
	User = object
		id: int
		email: string

pc.create("admin", User(id: 9, email: "user@example.com"))

assert pc.get("admin", User).email == "user@example.com"

assert pc.update("admin", User(id: 9, email: "admin@example.com")).email == "admin@example.com"

# Can also use option types when getting to avoid errors
import std/options
assert pc.get("doesntExst", Option[User]).isNone()
assert pc.get("admin", Option[User]).isSome()

```
