---
title: "Testing"
date: 2020-10-27T21:34:23+01:00
description: testing is important ! This is why i'm writing this hehe, juste to test !!!
draft: false
---

Here is some code to test !

```go
package main

import "fmt"

func main(){
  fmt.Println("without lang!")
}
```
and tadaaaaa....
```
#!/bin/bash

echo "with lang:"

exit 0
```
{{< code language="css" title="Really cool snippet" id="1" expand="Show" collapse="Hide" isCollapsed="true" >}}
pre {
  background: #1a1a1d;
  padding: 20px;
  border-radius: 8px;
  font-size: 1rem;
  overflow: auto;

  @media (--phone) {
    white-space: pre-wrap;
    word-wrap: break-word;
  }

  code {
    background: none !important;
    color: #ccc;
    padding: 0;
    font-size: inherit;
  }
}
{{< /code >}}
