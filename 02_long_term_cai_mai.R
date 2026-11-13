
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

analysis_name <- "long_term"
pine_site$to <- "2085-12"
climate_columns <- c("tmp_min", "tmp_max", "tmp_ave", "prcp", "srad",
                     "frost_days", "co2", "d13catm")
pine_climate <- aggregate(d_climate[, climate_columns],
                          by = list(month = d_climate$month), FUN = mean)
pine_climate <- pine_climate[order(pine_climate$month), ]
stopifnot(nrow(pine_climate) == 12, all(pine_climate$month == 1:12))
write.csv(pine_climate, "repeated_monthly_climate.csv", row.names = FALSE)

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
write.csv(monthly, paste0(analysis_name, "_monthly.csv"), row.names = FALSE)
write.csv(annual, paste0(analysis_name, "_annual.csv"), row.names = FALSE, na = "")
input_tables <- list(site = pine_site, species = pine_species, climate = pine_climate,
                     parameters = pine_parameters, size_dist = pine_sizeDist)
for (nm in names(input_tables)) {
  write.csv(input_tables[[nm]], paste0(" analysis_name, "_", nm, ".csv"),
            row.names = FALSE)
}
capture.output(sessionInfo(), file = paste0("outputs/", analysis_name, "_sessionInfo.txt"))

# plotting function
green <- "#176B5B"; blue <- "#2E65A7"; orange <- "#B65B26"
plot_panel <- function(x, y, title, ylab, color = green, xlab = "Stand age (years)") {
  plot(x, y, type = "n", main = title, xlab = xlab, ylab = ylab,
       col.main = "#18372F", bty = "l", las = 1)
  grid(col = "#E5E9E8")
  lines(x, y, col = color, lwd = 2.5)
}

# Maximum of sampled annual MAI values. An endpoint maximum is inconclusive.
peak_row <- which.max(annual$MAI_standing_m3_ha_yr)
peak <- annual[peak_row, ]
peak$interior_peak <- peak_row > 1 && peak_row < nrow(annual)
write.csv(peak, "mai_peak.csv", row.names = FALSE, na = "")

# CAI is assigned to its year-end; it is a preceding-year interval change,
# not an instantaneous derivative. Crossing and sampled MAI peak may differ.
gap <- annual$net_CAI_m3_ha_yr - annual$MAI_standing_m3_ha_yr
n <- nrow(annual)
i <- which(is.finite(gap[-n]) & is.finite(gap[-1]) & gap[-n] > 0 & gap[-1] <= 0)
crossings <- data.frame(age_from = annual$age[i], age_to = annual$age[i + 1],
                        year_from = annual$year[i], year_to = annual$year[i + 1])
write.csv(crossings, "cai_mai_crossings.csv", row.names = FALSE)

png("02_long_term_cai_mai.png", width = 1900, height = 1100, res = 170)
par(mfrow = c(1, 2), mar = c(4.8, 5.2, 3.5, 1), oma = c(3, 0, 3, 0))
plot_panel(annual$age, annual$volume, "Standing volume", "Volume (m3/ha)")
abline(v = peak$age, col = orange, lty = 3)
plot(annual$age, annual$net_CAI_m3_ha_yr, type = "n",
     ylim = range(c(annual$net_CAI_m3_ha_yr, annual$MAI_standing_m3_ha_yr), na.rm = TRUE),
     xlab = "Stand age (years)", ylab = "Increment (m3/ha/year)",
     main = "Annual and mean increment", bty = "l", las = 1)
grid(col = "#E5E9E8")
lines(annual$age, annual$net_CAI_m3_ha_yr, col = green, lwd = 2.5)
lines(annual$age, annual$MAI_standing_m3_ha_yr, col = blue, lwd = 2.5, lty = 2)
abline(v = peak$age, col = orange, lty = 3)
points(peak$age, peak$MAI_standing_m3_ha_yr, col = orange, pch = 16)
legend("bottomright", c("Net standing-volume CAI", "Standing-volume MAI", "Sampled MAI maximum"),
       col = c(green, blue, orange), lty = c(1, 2, 3), lwd = 2, bty = "n", cex = .8)
mtext("Scots pine | exploring the MAI peak", outer = TRUE, side = 3, font = 2, cex = 1.25)
mtext(sprintf("Peak standing-volume MAI: %.2f m3/ha/year at model age %.1f", peak$MAI_standing_m3_ha_yr, peak$age), outer = TRUE, side = 1, line = .2)
mtext("Repeated average weather | established initial stand | illustrative, unvalidated projection", outer = TRUE, side = 1, line = 1.4, cex = .8)
dev.off()

png("03_long_term_stand_structure.png", width = 1800, height = 1050, res = 170)
par(mfrow = c(1, 2), mar = c(4.8, 5.2, 3.5, 1), oma = c(2, 0, 2, 0))
plot_panel(annual$age, annual$stems_n, "Living stem density", "Stems/ha")
plot_panel(annual$age, annual$qmd_cm, "Quadratic mean diameter", "QMD (cm)", blue)
mtext("Stand structure accompanying the long-term projection", outer = TRUE, side = 3, font = 2)
mtext("QMD derived from basal area and density; simulated values, not field observations", outer = TRUE, side = 1, cex = .85)
dev.off()
print(peak)
print(crossings)
if (!peak$interior_peak) warning("Peak at boundary: an interior maximum is not established")
