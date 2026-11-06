port <- as.integer(Sys.getenv("GATE4_PORT"))
if (is.na(port)) stop("GATE4_PORT is required")
.libPaths(c("C:/Users/yjh14/AppData/Local/R/win-library/4.5", .libPaths()))
shiny::runApp(
  "apps/timeseries",
  host = "127.0.0.1",
  port = port,
  launch.browser = FALSE,
  quiet = TRUE
)
