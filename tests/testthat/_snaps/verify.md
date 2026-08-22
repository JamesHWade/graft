# graft_verify validates chats and returns a stable empty result

    Code
      conditionMessage(condition)
    Output
      [1] "`chat` must be an ellmer Chat object."

---

    Code
      conditionMessage(turns_condition)
    Output
      [1] "`chat$get_turns()` failed while reading recorded turns.\nCaused by error in `chat$get_turns()`:\n! turn failure"
