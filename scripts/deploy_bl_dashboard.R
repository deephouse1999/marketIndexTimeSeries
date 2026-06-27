find_repo_root <- function() {
  candidates <- unique(c(
    normalizePath(getwd(), winslash = "/", mustWork = TRUE),
    normalizePath(file.path(getwd(), ".."), winslash = "/", mustWork = FALSE)
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "apps", "dashboard", "app.R"))) {
      return(candidate)
    }
  }

  stop("Could not find repo root containing apps/dashboard/app.R.", call. = FALSE)
}

repo_root <- find_repo_root()
dashboard_dir <- file.path(repo_root, "apps", "dashboard")

if (!"rsconnect" %in% rownames(installed.packages())) {
  stop("Package 'rsconnect' is required to deploy this app.")
}

if (nrow(rsconnect::accounts()) == 0) {
  if (nzchar(Sys.getenv("SHINYAPPS_TOKEN")) && nzchar(Sys.getenv("SHINYAPPS_SECRET"))) {
    rsconnect::setAccountInfo(
      name = "deephouse1999",
      token = Sys.getenv("SHINYAPPS_TOKEN"),
      secret = Sys.getenv("SHINYAPPS_SECRET")
    )
  } else {
    stop(
      paste(
        "No shinyapps.io account is registered on this local R session.",
        "Run this once in R with your token and secret:",
        "rsconnect::setAccountInfo(name = 'deephouse1999', token = 'YOUR_TOKEN', secret = 'YOUR_SECRET')",
        sep = "\n"
      ),
      call. = FALSE
    )
  }
}

rsconnect::deployApp(
  appDir = dashboard_dir,
  appName = "us_econ_dashboard",
  account = "deephouse1999",
  launch.browser = FALSE
)
