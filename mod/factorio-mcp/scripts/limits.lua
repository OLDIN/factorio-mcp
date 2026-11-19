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
  -- A whole-map job covers the bounding box of a surface's generated chunks; bound its size (in
  -- chunks) and how many jobs run at once.
  MAX_JOB_CHUNKS = 250000,
  MAX_RUNNING_JOBS = 4,
  -- `resources`: radius bound, and the most resource tiles read in one tick; above it the service
  -- runs job kind `resources` (measured ~1.5-2.2 us per tile read, so this stays around 2 ms).
  MAX_RESOURCES_RADIUS = 128,
  SYNC_MAX_RESOURCE_TILES = 1000,
  -- `transport`: belt contents are read from at most this many belts per call (~4 us each).
  MAX_TRANSPORT_BELT_READS = 100,
  -- `transport`: read every entity up to this many in the circle (~1-1.5 us each); above it counts come
  -- per name and at most TRANSPORT_SAMPLE_READS inserters and fluid boxes are read.
  TRANSPORT_FULL_READ_MAX = 600,
  TRANSPORT_SAMPLE_READS = 300,
}
