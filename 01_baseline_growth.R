# BASELINE: 2001-2010 example weather; pine only.
# install.packages("r3PG") 
if (!requireNamespace("r3PG", quietly = TRUE)) stop("Install r3PG first")
library(r3PG)

# Difference of consecutive annual standing stocks; first value is missing.
calculate_increment <- function(volume) {
  c(NA_real_, diff(volume))
}

# Extract pine from the package mixed-species example.
pine_species <- d_species[d_species$species == "Pinus sylvestris", , drop = FALSE]
pine_parameters <- d_parameters[, c("parameter", "Pinus sylvestris"), drop = FALSE]
pine_sizeDist <- d_sizeDist[, c("parameter", "Pinus sylvestris"), drop = FALSE]
pine_site <- d_site
stopifnot(nrow(pine_species) == 1)

analysis_name <- "baseline"
pine_climate <- d_climate

settings <- list(light_model = 2, transp_model = 2, phys_model = 2,
                 height_model = 1, correct_bias = 0, calculate_d13c = 0)
pine_output <- run_3PG(
  site = pine_site, species = pine_species, climate = pine_climate,
  thinning = NULL, parameters = pine_parameters, size_dist = pine_sizeDist,
  settings = settings, check_input = TRUE, df_out = TRUE
)

# Match variables by date rather than assuming the same output row order.
variables <- c("age", "volume", "dbh", "height", "basal_area", "stems_n")
z <- pine_output[pine_output$variable == "volume", ]
monthly <- data.frame(date = sort(z$date))
for (v in variables) {
  z <- pine_output[pine_output$variable == v, c("date", "value")]
  stopifnot(!anyDuplicated(z$date))
  monthly[[v]] <- z$value[match(monthly$date, z$date)]
}
expected <- seq(as.Date(paste0(pine_site$from, "-01")),
                as.Date(paste0(pine_site$to, "-01")), by = "month")
stopifnot(nrow(monthly) == length(expected),
          identical(format(monthly$date, "%Y-%m"), format(expected, "%Y-%m")),
          all(is.finite(as.matrix(monthly[variables]))),
          all(monthly$age > 0), all(monthly$stems_n > 0),
          all(as.matrix(monthly[setdiff(variables, "age")]) >= 0))

# December endpoints: annual stocks, not sums of monthly standing volume.
annual <- monthly[format(monthly$date, "%m") == "12", ]
annual$year <- as.integer(format(annual$date, "%Y"))
stopifnot(all(diff(annual$year) == 1))
annual$net_CAI_m3_ha_yr <- calculate_increment(annual$volume)
annual$MAI_standing_m3_ha_yr <- annual$volume / annual$age
annual$qmd_cm <- sqrt(40000 * annual$basal_area / (pi * annual$stems_n))
rownames(annual) <- NULL

# Arithmetic checks; these are not ecological validation against observations.
stopifnot(identical(calculate_increment(c(100, 110, 106)), c(NA_real_, 10, -4)),
          abs(sqrt(40000 * (pi * 10) / (pi * 1000)) - 20) < 1e-10)
write.csv(monthly, paste0("outputs/", analysis_name, "_monthly.csv"), row.names = FALSE)
write.csv(annual, paste0("outputs/", analysis_name, "_annual.csv"), row.names = FALSE, na = "")
saveRDS(list(site = pine_site, species = pine_species, climate = pine_climate,
             parameters = pine_parameters, size_dist = pine_sizeDist,
             settings = settings, thinning = NULL),
        paste0("outputs/", analysis_name, "_inputs.rds"))
dir.create("outputs/inputs", showWarnings = FALSE)
input_tables <- list(site = pine_site, species = pine_species, climate = pine_climate,
                     parameters = pine_parameters, size_dist = pine_sizeDist)
for (nm in names(input_tables)) {
  write.csv(input_tables[[nm]], paste0("outputs/inputs/", analysis_name, "_", nm, ".csv"),
            row.names = FALSE)
}
capture.output(sessionInfo(), file = paste0("outputs/", analysis_name, "_sessionInfo.txt"))

# Simple reusable plotting function, defined here to keep this script standalone.
green <- "#176B5B"; blue <- "#2E65A7"; orange <- "#B65B26"
plot_panel <- function(x, y, title, ylab, color = green, xlab = "Stand age (years)") {
  plot(x, y, type = "n", main = title, xlab = xlab, ylab = ylab,
       col.main = "#18372F", bty = "l", las = 1)
  grid(col = "#E5E9E8")
  lines(x, y, col = color, lwd = 2.5)
}

png("figures/01_baseline_growth.png", width = 1900, height = 1350, res = 170)
par(mfrow = c(2, 2), mar = c(4.5, 5.2, 3, 1), oma = c(2, 0, 2.5, 0))
plot_panel(monthly$date, monthly$volume, "Standing volume", "Volume (m3/ha)", xlab = "Calendar year")
plot_panel(monthly$date, monthly$dbh, "Mean diameter", "DBH (cm)", blue, "Calendar year")
plot_panel(monthly$date, monthly$basal_area, "Stand basal area", "Basal area (m2/ha)", green, "Calendar year")
plot_panel(annual$year, annual$net_CAI_m3_ha_yr, "Annual net volume increment", "Increment (m3/ha/year)", blue, "Calendar year")
mtext("Scots pine | baseline growth and yield", outer = TRUE, side = 3, font = 2, cex = 1.25)
mtext("r3PG example inputs | single-species application | no thinning | simulated values", outer = TRUE, side = 1, cex = .85)
dev.off()
print(annual[, c("year", "age", "volume", "net_CAI_m3_ha_yr", "MAI_standing_m3_ha_yr")])
