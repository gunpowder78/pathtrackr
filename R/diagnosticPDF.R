#' Track an animal's movement across a series of still frames with diagnostic plots
#'
#' \code{diagnosticPDF} contains the same function as the core \code{pathtrackr::trackPath} function but, in addition, produces a pdf with disgnostic plots for troubleshooting problematic animals and tracks. A set of six plots for each frame allow the user to view the tracking behaviour of the function on a frame by frame basis.
#' @inheritParams trackPath
#' @details See documentation for \code{\link{trackPath}}.
#' @return A list containing a matrix of xy co-ordinates of the animal in each frame, a matrix of movement data including the distance, velocity and trajectories of movement between frames, summary statistics, and a diagnostic PDF.
#' @importFrom raster raster extent select
#' @importFrom viridis viridis
#' @importFrom pbapply pboptions pbapply pblapply
#' @importFrom abind abind
#' @importFrom EBImage bwlabel opening thresh rmObjects
#' @importFrom imager isoblur as.cimg
#' @importFrom plyr aaply count create_progress_bar progress_text
#' @export
diagnosticPDF = function(dirpath, xarena, yarena, fps = 30, box = 1, jitter.damp = 0.9) {

  require(raster, quietly = TRUE)

  if (length(dir(dirpath, "*.jpg")) > 0) {
    file.list = list.files(dirpath, full.names = TRUE)
  } else {
    stop("No files were found... check that the path to your directory is correct and that it contains only jpg files.")
  }

  # Set progress bar options
  pboptions(type = "txt", char = ":")
  pbapp = create_progress_bar(name = "text", style = 3, char = ":", width = 50)

  # Load all frames into an array
  message("Loading video frames...")
  flush.console()
  cube = abind(pblapply(file.list, greyJPEG), along = 3)

  # Crop array to area of interest if needed
  message("Click once on the top left corner of your arena, followed by clicking once on the bottom right corner of your arena, to define the opposing corners of the entire arena...")
  flush.console()
  plot(raster(file.list[1], band = 2), col = gray.colors(256), asp = 1)
  bg.crop = base::as.vector(extent(select(raster(file.list[1], band = 2))))
  cube = cube[(dim(cube)[1] - bg.crop[3]):(dim(cube)[1] - bg.crop[4]), bg.crop[1]:bg.crop[2], 1:length(file.list)]

  # Get aniaml tracking box in first frame
  bg.ref = reflect(cube[,,1])
  bg.dim = dim(bg.ref)
  message("Imagine a rectangle that defines the minimum region of your arena that contains your whole animal. Click once to define the top left corner of this rectangle, followed by clicking once to define the bottom right corner of this rectangle...")
  flush.console()
  plot(raster(bg.ref, xmn = 0, xmx = bg.dim[2], ymn = 0, ymx = bg.dim[1]), col = gray.colors(256), asp = 1)
  animal.crop = round(base::as.vector(extent(select(raster(bg.ref, xmn = 0, xmx = bg.dim[1], ymn = 0, ymx = bg.dim[2])))))

  ref.x1 = animal.crop[1]
  ref.x2 = animal.crop[2]
  ref.y1 = animal.crop[4]
  ref.y2 = animal.crop[3]
  dim.x = abs(ref.x1 - ref.x2)
  dim.y = abs(ref.y1 - ref.y2)

  # Generate background reference frame
  message("Generating background reference frame...")
  flush.console()
  cube.med = pbapply(cube, 1:2, median)

  # Subtract background from all frames
  message("Subtracting background from each frame...")
  flush.console()
  cube.bgs = aaply(cube, 3, function(x) {abs(x - cube.med)}, .progress = pbapp)
  cube.bgs = aperm(cube.bgs, c(2,3,1))

  message("Tracking animal...")
  flush.console()
  # Loop through frames fitting tracking box and extracting animal position etc.
  xpos = c()
  ypos = c()
  animal.size = c()
  breaks = c()
  break.count = 1
  animal.last = c()
  blur = 5
  min.animal = 0.25
  max.animal = 1.75
  temp.movement = c()

  pbloop = txtProgressBar(min = 0, max = length(file.list), style = 3, char = ":", width = 50)

  diag_fig = paste(paste(unlist(strsplit(dirpath, "/"))[1:(length(unlist(strsplit(dirpath, "/"))) - 1)], collapse = "/"), "/", unlist(strsplit(dirpath, "/"))[length(unlist(strsplit(dirpath, "/")))], "_diagnostic.pdf", sep = "")
  pdf(file = diag_fig, width = 12, height = 8)

  for (i in 1:dim(cube.bgs)[3]) {

    # For first frame...
    if (i == 1) {

      # Find, segment and label blobs, then fit an ellipse
      tbox = reflect(cube.bgs[,,i][ref.y1:ref.y2,ref.x1:ref.x2])
      tbox.bin = as.matrix(bwlabel(opening(thresh(isoblur(as.cimg(tbox), blur)))))
      animal = ellPar(which(tbox.bin == 1, arr.ind = TRUE))
      animal.last = which(tbox.bin == 1)

      # Correct xy positions relative to entire frame and store
      xpos[i] = round(animal$centre[2] + ref.x1)
      ypos[i] = round(animal$centre[1] + ref.y2)

      # Store animal size
      animal.size[i] = animal$area

      par(mfrow = c(2, 3), mar = c(5, 5, 2, 3) + 0.1, cex.axis = 1.5, cex.lab = 1.5)

      plot(1, 1, xlim = c(1, bg.dim[1]), ylim = c(1, bg.dim[2]), type = "n", xaxs = "i", yaxs = "i", xaxt = "n", yaxt = "n", xlab = "", ylab = "", bty = "n")
      rasterImage(as.raster(reflect(cube[,,i])), 1, 1, bg.dim[1], bg.dim[2])

      plot(raster(reflect(cube.bgs[,,i])), legend = FALSE, xaxs = "i", yaxs = "i", cex = 1.5, col = viridis(256))
      rect(ref.x1/bg.dim[2], ref.y1/bg.dim[1], ref.x2/bg.dim[2], ref.y2/bg.dim[1], border = "yellow", lwd = 1.5)

      plot(raster(reflect(tbox)), legend = FALSE, xaxs = "i", yaxs = "i", cex = 1.5, col = viridis(256))
      points(round(animal$centre[2])/dim(tbox)[2], round(animal$centre[1])/dim(tbox)[1], col = "red", pch = 16, cex = 2.5)

      plot(xpos * (xarena/bg.dim[2]), ypos * (yarena/bg.dim[2]), col = "#08306B", type = "l", lwd = 2, pch = 16, xlim = c(0, bg.dim[2] * (xarena/bg.dim[2])), ylim = c(0, bg.dim[1] * (yarena/bg.dim[1])), xlab = "Distance (mm)", ylab = "Distance (mm)", xaxs = "i", yaxs = "i", cex = 1.5)

      plot(temp.movement[, 3], cumsum(temp.movement[, 1]), type = "l", lwd = 2, xlab = "Time (s)", ylab = "Distance (mm)", bty = "l", xlim = c(0, length(file.list) * (1/fps)), ylim = c(0, 0.1), col = "#08306B", cex = 1.5)

      plot(temp.movement[, 3], temp.movement[, 2], type = "l", lwd = 1.5, xlab = "Time (s)", ylab = "Velocity (mm/s)", bty = "l", xlim = c(0, length(file.list) * (1/fps)), ylim = c(0, 0.1), col = "#08306B", cex = 1.5)

      # For the remaining frames...
    } else {

      # Calculate co-oordinates to redraw tracking box around last position
      if (!is.na(tail(xpos, 1))) {x1 = xpos[i - 1] - dim.x * box}
      if (x1 < 0) {x1 = 0}
      if (x1 > bg.dim[2]) {x1 = bg.dim[2]}
      if (!is.na(tail(xpos, 1))) {x2 = xpos[i - 1] + dim.x * box}
      if (x2 < 0) {x2 = 0}
      if (x2 > bg.dim[2]) {x2 = bg.dim[2]}
      if (!is.na(tail(ypos, 1))) {y1 = ypos[i - 1] - dim.y * box}
      if (y1 < 0) {y1 = 0}
      if (y1 > bg.dim[1]) {y1 = bg.dim[1]}
      if (!is.na(tail(ypos, 1))) {y2 = ypos[i - 1] + dim.y * box}
      if (y2 < 0) {y2 = 0}
      if (y2 > bg.dim[1]) {y2 = bg.dim[1]}

      # Find, segment and label blobs, then fit an ellipse
      tbox = reflect(cube.bgs[,,i][y2:y1,x1:x2])
      tbox.bin = as.matrix(bwlabel(opening(thresh(isoblur(as.cimg(tbox), blur)))))

      # Calculate proportion of overlapping pixels from between current & previous frame
      animal.new = which(tbox.bin == 1)
      animal.move = (length(na.omit(match(animal.last, animal.new))))/(max(c(length(animal.last), length(animal.new))))
      animal.last = animal.new

      # Check if animal is of ~right size
      if (length(which(tbox.bin == 1)) > mean(animal.size, na.rm = TRUE)*min.animal & length(which(tbox.bin == 1)) < mean(animal.size, na.rm = TRUE)*max.animal) {

        # Check animal has moved my more than 10% of size
        if (animal.move < jitter.damp) {

          animal = ellPar(which(tbox.bin == 1, arr.ind = TRUE))

          # Correct xy positions relative to entire frame and store
          xpos[i] = round(animal$centre[2] + x1)
          ypos[i] = round(animal$centre[1] + y1)

          # Store animal size
          animal.size[i] = animal$area

        } else {

          # Store last known position of animal and size
          xpos[i] = xpos[i - 1]
          ypos[i] = ypos[i - 1]
          animal.size[i] = animal.size[i - 1]
        }

      } else {

        frame.break = reflect(cube.bgs[,,i])
        frame.break.bin = as.matrix(bwlabel(opening(thresh(isoblur(as.cimg(frame.break), blur)))))
        blob.pixcount = as.matrix(count(frame.break.bin[frame.break.bin > 0]))

        if (nrow(blob.pixcount) > 1) {
          frame.break.bin = rmObjects(frame.break.bin, blob.pixcount[blob.pixcount[,2] < mean(animal.size, na.rm = TRUE)*min.animal | blob.pixcount[,2] > mean(animal.size, na.rm = TRUE)*max.animal,1])
        }

        if (length(which(frame.break.bin == 1)) > mean(animal.size, na.rm = TRUE)*min.animal & length(which(frame.break.bin == 1)) < mean(animal.size, na.rm = TRUE)*max.animal) {

          animal = ellPar(which(frame.break.bin == 1, arr.ind = TRUE))

          # Correct xy positions relative to entire frame and store
          xpos[i] = round(animal$centre[2])
          ypos[i] = bg.dim[1] - round(animal$centre[1])

          # Store animal size
          animal.size[i] = animal$area

        } else {

          # Mark position and size as unknown
          xpos[i] = NA
          ypos[i] = NA
          animal.size[i] = NA

          # Store breaks
          breaks[break.count] = i
          break.count = break.count + 1
        }
      }

      temp.time = seq(0, length.out = length(xpos), by = 1/fps)
      temp.distance = c()
      temp.velocity = c()
      temp.count = 1
      for (l in 2:length(xpos)) {
        temp.A = abs(xpos[l] - xpos[l - 1]) * (xarena/bg.dim[2])
        temp.B = abs(ypos[l] - ypos[l - 1]) * (yarena/bg.dim[1])
        temp.distance[temp.count] = sqrt((temp.A^2) + (temp.B^2))
        temp.velocity[temp.count] = temp.distance[temp.count]/(1/fps)
        temp.count = temp.count + 1
      }
      temp.movement = matrix(ncol = 3, nrow = temp.count)
      colnames(temp.movement) = c("distance", "velocity", "time")
      temp.movement[, 1] = c(0, temp.distance)
      temp.movement[, 2] = c(0, temp.velocity)
      temp.movement[, 3] = c(temp.time)

      par(mfrow = c(2, 3), mar = c(5, 5, 2, 3) + 0.1, cex.axis = 1.5, cex.lab = 1.5)

      plot(1, 1, xlim = c(1, bg.dim[1]), ylim = c(1, bg.dim[2]), type = "n", xaxs = "i", yaxs = "i", xaxt = "n", yaxt = "n", xlab = "", ylab = "", bty = "n")
      rasterImage(as.raster(reflect(cube[,,i])), 1, 1, bg.dim[1], bg.dim[2])

      plot(raster(reflect(cube.bgs[,,i])), legend = FALSE, xaxs = "i", yaxs = "i", cex = 1.5, col = viridis(256))
      rect(x1/bg.dim[2], y1/bg.dim[1], x2/bg.dim[2], y2/bg.dim[1], border = "yellow", lwd = 1.5)

      plot(raster(reflect(tbox)), legend = FALSE, xaxs = "i", yaxs = "i", cex = 1.5, col = viridis(256))
      points(round(animal$centre[2])/dim(tbox)[2], round(animal$centre[1])/dim(tbox)[1], col = "red", pch = 16, cex = 2.5)

      segments((xpos[i - 1] - x1)/ncol(tbox), (ypos[i - 1] - y1)/nrow(tbox), (xpos[i] - x1)/ncol(tbox), (ypos[i] - y1)/nrow(tbox), col = "red", pch = 16, lwd = 3)

      plot(xpos * (xarena/bg.dim[2]), ypos * (yarena/bg.dim[2]), col = "#08306B", type = "l", lwd = 2, pch = 16, xlim = c(0, bg.dim[2] * (xarena/bg.dim[2])), ylim = c(0, bg.dim[1] * (yarena/bg.dim[1])), xlab = "Distance (mm)", ylab = "Distance (mm)", xaxs = "i", yaxs = "i", cex = 1.5)

      cumDistance = cumsum(ifelse(is.na(temp.movement[, 1]), 0, temp.movement[, 1])) + temp.movement[, 1] * 0
      plot(temp.movement[, 3], cumDistance, type = "l", lwd = 2, xlab = "Time (s)", ylab = "Distance (mm)", bty = "l", xlim = c(0, length(file.list) * (1/fps)), col = "#08306B", cex = 1.5)

      plot(temp.movement[, 3], temp.movement[, 2], type = "l", lwd = 1.5, xlab = "Time (s)", ylab = "Velocity (mm/s)", bty = "l", xlim = c(0, length(file.list) * (1/fps)), col = "#08306B", cex = 1.5)

    }
    setTxtProgressBar(pbloop, i)
  }

  dev.off()

  time = seq(0, length.out = length(xpos), by = 1/fps)
  distance = c()
  abs.angle = c()
  rel.angle = c()
  velocity = c()
  count = 1
  for (j in 2:length(xpos)) {
    A = (xpos[j] - xpos[j - 1]) * (xarena/bg.dim[2])
    B = (ypos[j] - ypos[j - 1]) * (yarena/bg.dim[1])
    distance[count] = sqrt((A^2) + (B^2))
    abs.angle[count] = ifelse(distance[count] != 0 | count == 1, (atan2(A, B * -1) * (180/pi)) %% 360, abs.angle[count - 1])
    rel.angle[count] = ((((abs.angle[count] - abs.angle[count - 1]) %% 360) + 540) %% 360) - 180
    velocity[count] = distance[count]/(1/fps)
    count = count + 1
  }

  movement = matrix(ncol = 5, nrow = count)
  colnames(movement) = c("distance", "abs.angle", "rel.angle", "velocity", "time")
  movement[, 1] = c(0, distance)
  movement[, 2] = c(0, abs.angle)
  movement[, 3] = c(0, abs.angle[1], rel.angle[2:length(rel.angle)])
  movement[, 4] = c(0, velocity)
  movement[, 5] = c(time)
  total.distance = round(sum(movement[,1]))
  mean.velocity = mean(movement[,4])
  total.duration = movement[nrow(movement),5]

  if (length(breaks) > 0) {
    warning("Tracking was not possible for ", length(breaks), " frames: you can proceed with this tracked path but you might consider using a higher frame rate or increasing the tracking 'box' size to improve the result.")
    flush.console()
  }

  rm(cube)

  return(list(position = cbind(xpos, ypos), dim.pix = c(bg.dim[2], bg.dim[1]), dim.arena = c(xarena, yarena), fps = fps, movement = movement, total.distance = total.distance, mean.velocity = mean.velocity, total.duration = total.duration, breaks = breaks))

}
