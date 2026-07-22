time_ingest_schema <- function() {
  schema <- modified_ingest_schema(kg_schema(tempest_manifest_path()))
  activity <- schema$manifest$classes$Activity

  event_time <- activity$slots$name
  event_time$name <- "event_time"
  event_time$column <- "event_time"
  event_time$range <- "time"
  event_time$relational_type <- "TIME"
  event_time$required <- TRUE

  reminder_times <- event_time
  reminder_times$name <- "reminder_times"
  reminder_times$column <- NULL
  reminder_times$multivalued <- TRUE
  reminder_times$ordered <- FALSE
  reminder_times$required <- FALSE

  activity$slots$event_time <- event_time
  activity$slots$reminder_times <- reminder_times
  activity$slots <- activity$slots[sort(
    names(activity$slots),
    method = "radix"
  )]
  activity$relations <- list("Activity.reminder_times")
  schema$manifest$classes$Activity <- activity

  schema$manifest$tables$Activity$columns <- append(
    schema$manifest$tables$Activity$columns,
    list(list(
      name = "event_time",
      type = "TIME",
      nullable = FALSE,
      primary_key = FALSE,
      slot = "event_time",
      foreign_key = NULL
    ))
  )
  schema$manifest$relations <- append(
    schema$manifest$relations,
    list(list(
      columns = list(
        list(
          name = "owner_id",
          type = "VARCHAR",
          nullable = FALSE,
          foreign_key = list(class = "Activity", slot = "id")
        ),
        list(name = "position", type = "BIGINT", nullable = TRUE),
        list(name = "value", type = "TIME", nullable = FALSE)
      ),
      kind = "value",
      name = "Activity.reminder_times",
      ordered = FALSE,
      owner_class = "Activity",
      owner_table = "activity",
      predicate = "https://w3id.org/graft/reminderTime",
      slot = "reminder_times",
      table = "activity__reminder_times"
    ))
  )
  refresh_schema_structural_digest(schema)
}
