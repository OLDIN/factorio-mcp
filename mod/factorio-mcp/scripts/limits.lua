-- Size limits of the RCON conversation. Values are set from the measurements in docs/measurements.md.
return {
  -- Largest JSON reply a paged command should build (bytes). Measured in Task 4:
  -- Factorio delivers multi-megabyte RCON responses intact in a single packet.
  -- 48,000 bytes provides a conservative page budget (~36 KB raw JSON) ensuring fast serialization.
  RESPONSE_BUDGET_BYTES = 48000,
  -- Largest "<sub> <json>" parameter string the dispatcher accepts (bytes).
  MAX_PARAM_BYTES = 1000,
  -- `area` answers at once up to this radius (tiles); larger areas must run as a tick-split job.
  MAX_SYNC_AREA_RADIUS = 64,
  -- Sanity bound for a tick-split `area` job (cost grows with the area, spread over ticks).
  MAX_JOB_AREA_RADIUS = 1000,
  -- A job's chunk list is built in one go and kept in `storage`: bound it, and bound how many run at once.
  MAX_JOB_CHUNKS = 250000,
  MAX_RUNNING_JOBS = 4,
}
