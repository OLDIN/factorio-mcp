-- Size limits of the RCON conversation. Values are set from the measurements in docs/measurements.md.
return {
  -- Largest JSON reply a paged command should build (bytes). Provisional until measured (Task 4).
  RESPONSE_BUDGET_BYTES = 4000,
  -- Largest "<sub> <json>" parameter string the dispatcher accepts (bytes).
  MAX_PARAM_BYTES = 1000,
}
