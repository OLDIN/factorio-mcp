-- Size limits of the RCON conversation. Values are set from the measurements in docs/measurements.md.
return {
  -- Largest JSON reply a paged command should build (bytes). Measured in Task 4:
  -- Factorio delivers multi-megabyte RCON responses intact in a single packet.
  -- 48,000 bytes provides a conservative page budget (~36 KB raw JSON) ensuring fast serialization.
  RESPONSE_BUDGET_BYTES = 48000,
  -- Largest "<sub> <json>" parameter string the dispatcher accepts (bytes).
  MAX_PARAM_BYTES = 1000,
}
