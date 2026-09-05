# host collisions are explicit and must be checked before tool composition

    Code
      chat$set_tools(combined)
    Message
      Replacing existing graft_get tool.

---

    Code
      deputy::Agent$new(chat = clean_chat, tools = combined)
    Condition
      Error in `validate_tool_batch()`:
      ! Duplicate tool name "graft_get" in the registration batch.

