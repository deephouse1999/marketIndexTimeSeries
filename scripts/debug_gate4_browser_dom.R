suppressPackageStartupMessages({ library(callr); library(chromote); library(httr); library(jsonlite) })
repo <- normalizePath(".", winslash = "/", mustWork = TRUE)
app_dir <- file.path(repo, "apps", "timeseries")
lib <- "C:/Users/yjh14/AppData/Local/R/win-library/4.5"
p <- callr::r_bg(function(app_dir, lib) { .libPaths(c(lib, .libPaths())); shiny::runApp(app_dir, host="127.0.0.1", port=5450, launch.browser=FALSE, quiet=TRUE) }, args=list(app_dir,lib), supervise=TRUE)
on.exit(try(p$kill(), silent=TRUE), add=TRUE)
for(i in 1:100) { if(tryCatch({httr::GET("http://127.0.0.1:5450/", httr::timeout(1)); TRUE}, error=function(e) FALSE)) break; Sys.sleep(.05) }
b <- ChromoteSession$new(); on.exit(b$close(), add=TRUE)
b$Page$navigate("http://127.0.0.1:5450/"); b$Page$loadEventFired(wait_=TRUE)
Sys.sleep(1)
click <- b$Runtime$evaluate(expression="(() => { const x=[...document.querySelectorAll('.navbar a')].find(v=>v.textContent.trim()==='SOX Constituents'); if(!x)return false;x.click();return true;})()",returnByValue=TRUE)$result$value
Sys.sleep(5)
evaluate <- function(x) b$Runtime$evaluate(expression=x, returnByValue=TRUE)$result$value
cat("clicked=",click,"\n")
cat("busy=",evaluate("document.body.classList.contains('shiny-busy')"),"\n")
cat("output_exists=",evaluate("!!document.querySelector('#sox_benchmark_plot')"),"\n")
cat("desc_classes=",paste(evaluate("[...document.querySelectorAll('#sox_benchmark_plot *')].map(x=>x.className&&String(x.className)).filter(Boolean).slice(0,20)"),collapse=" | "),"\n")
cat("body_tail=",substr(evaluate("document.body.innerText"),1,1200),"\n")
cat("logs=",paste(unlist(b$Runtime$evaluate(expression="document.querySelector('#sox_benchmark_plot')?.innerHTML?.slice(0,1000)||''",returnByValue=TRUE)$result$value),collapse=""),"\n")
