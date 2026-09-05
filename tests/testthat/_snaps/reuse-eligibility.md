# Archive and restore change consultation without erasing accepted history

    Code
      tool()
    Condition
      Error:
      ! Reuse is not authorized.

---

    Code
      tool()
    Condition
      Error:
      ! Reuse is not authorized.

---

    Code
      restored()
    Condition
      Error:
      ! Reuse is not authorized.

---

    Code
      restored()
    Condition
      Error:
      ! Reuse is not authorized.

# host-owned supersession rejects cycles and preserves separate identities

    Code
      example$reuse_closure(old, cyclic)
    Condition
      Error:
      ! Dependency cycles require review.

---

    Code
      tool()
    Condition
      Error:
      ! Reuse is not authorized.

