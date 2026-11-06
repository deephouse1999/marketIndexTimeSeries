locale_result <- Sys.setlocale("LC_CTYPE", "Korean_Korea.utf8")
if (is.na(locale_result) || !grepl("utf8", locale_result, ignore.case = TRUE)) {
  stop("UTF-8 Korean locale is required for official ECOS item-name validation")
}
source(file.path("scripts", "register_ecos_series_gate2.R"), encoding = "UTF-8")

