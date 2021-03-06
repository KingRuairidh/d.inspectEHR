library(d.inspectEHR)
library(tidyverse)
library(dbplyr)
library(patchwork)

## Put your normal connection details in below.
ctn <- DBI::dbConnect()

## And put your schema inside the quotes:
schema <- ""

meas <- tbl(ctn, in_schema(schema, "measurement")) %>%
  group_by(measurement_concept_id) %>%
  tally() %>%
  collect() %>%
  mutate(across(everything(), as.integer))

dq_ref <- d.inspectEHR:::dq_ref
dq_ans <- d.inspectEHR:::dq_ans
is.integer64 <- d.inspectEHR:::is.integer64

meas_dq <- dq_ref %>%
  filter(concept_id %in% meas$measurement_concept_id) %>%
  select(concept_id, long_name, target_column)

meas_units <-  tbl(ctn, in_schema(schema, "measurement")) %>%
  distinct(.data$unit_concept_id) %>%
  collect() %>%
  pull() %>%
  as.integer()

meas_operator <-  tbl(ctn, in_schema(schema, "measurement")) %>%
  distinct(.data$operator_concept_id) %>%
  collect() %>%
  pull() %>%
  as.integer()

meas_dict1 <- mini_dict(ctn, schema, meas_units)
meas_dict2 <- mini_dict(ctn, schema, meas_operator)
meas_dict <- bind_rows(meas_dict1, meas_dict2)

for (i in seq_along(meas_dq$concept_id)) {

  current_concept <- meas_dq$concept_id[i]
  current_name <- meas_dq$long_name[meas_dq$concept_id == current_concept]
  target_col <- meas_dq$target_column[meas_dq$concept_id == current_concept]

  curr_title <- stringr::str_sub(current_name, 1, 30)
  if (nchar(curr_title) >= 30) {
    curr_title <- paste0(curr_title, "...")
  }

  print(paste0(current_concept, ": ", curr_title))

  working <- tbl(ctn, in_schema(schema, "measurement")) %>%
    filter(measurement_concept_id %in% !! current_concept) %>%
    collect() %>%
    mutate(across(where(is.integer64), as.integer)) %>%
    mutate(across(c(contains("date"), -contains("datetime")), as.Date))

  working_unit <- meas_dict %>%
    filter(concept_id %in% unique(working$unit_concept_id))

  single_units <- nrow(working_unit) == 1
  label_units <- working_unit[1,"concept_name",drop = TRUE]
  measure_n <- nrow(working)

  print(single_units)
  print(label_units)

  working <- left_join(
    working,
    tbl(ctn, in_schema(schema, "visit_occurrence")) %>%
      select(visit_occurrence_id, visit_start_datetime, visit_end_datetime) %>%
      collect(),
    by = "visit_occurrence_id")

  boundaries <- working %>%
    summarise(
      before = sum(measurement_datetime < visit_start_datetime, na.rm = TRUE),
      after = sum(measurement_datetime > visit_end_datetime, na.rm = TRUE)
    ) %>%
    tidyr::pivot_longer(everything(), names_to = "condition", values_to = "count")

  dup <- working %>%
    select(.data$person_id, .data$measurement_datetime, .data[[target_col]]) %>%
    janitor::get_dupes(everything()) %>%
    tally(name = "count") %>%
    tibble::add_column(condition = "duplications", .before = TRUE)

  miss <- tibble::tribble(
    ~condition, ~count,
    "no visit", sum(is.na(working$visit_occurrence_id))
  )

  bind_rows(boundaries, dup, miss) %>%
    mutate(
      total = measure_n,
      `p` = round((count/total)*100, 0),
      tolerance = c(1, 1, 1, 100)
    )

  if (target_col == "value_as_number") {
    val_dist <- working %>%
      select(value_as_number) %>%
      ggplot(aes(x = value_as_number)) +
      geom_density() +
      theme_classic() +
      labs(x = label_units)
  } else {
    opt <- dq_ans[dq_ans$concept_id == current_concept, c("option_concept_id", "option_name")]

    val_dist <- working %>%
      select(value_as_concept_id) %>%
      group_by(value_as_concept_id) %>%
      tally() %>%
      mutate(value_as_concept_id = factor(
        value_as_concept_id,
        levels = opt$option_concept_id,
        labels = opt$option_name
      )) %>%
      ggplot(aes(
        x = value_as_concept_id)) +
      geom_point(aes(y = n)) +
      geom_segment(aes(
        y = 0,
        yend = n,
        xend = as.factor(value_as_concept_id))) +
      theme_classic() +
      labs(y = "number of respones", x = "categories") +
      theme(axis.title.y = element_blank()) +
      coord_flip()
  }

  # timing distribution
  timing_dist <- working %>%
    select(measurement_datetime) %>%
    mutate(measurement_datetime = hms::as_hms(measurement_datetime)) %>%
    ggplot(aes(x = measurement_datetime)) +
    geom_density() +
    theme_classic() +
    labs(x = "time of sample")

  # samples over time
  sample_timing <- working %>%
    select(measurement_date) %>%
    group_by(measurement_date) %>%
    tally() %>%
    ggplot(aes(x = measurement_date, y = n)) +
    geom_path() +
    theme_classic() +
    labs(x = "measurement date", y = "daily samples")

  (val_dist | timing_dist) / sample_timing

}
