<p align="center">
	<img src="https://i.postimg.cc/rFD9YSMm/1.png" width="100%" />
</p>

## **Fake-HDR**

This script converts standard SDR images into [Ultra HDR JPEGs](https://developer.android.com/media/platform/hdr-image-format) using a synthesized gainmap. On HDR-capable displays the images will appear brighter and punchier than their SDR counterparts. On SDR displays they look identical to the original.

## **Core Components**

* [FFmpeg](https://ffmpeg.org/) - Used for image conversion and gainmap generation
* [libultrahdr](https://github.com/google/libultrahdr) - Google's Ultra HDR library, provides the `ultrahdr_app` binary that assembles the final image

## **Features**

* Accepts a single image or an entire directory as input
* When given a directory, outputs all converted images into an `HDR/` subfolder
* Automatically builds `ultrahdr_app` from source if it is not present
* Detects your package manager (pacman, apt, dnf) and tells you exactly what to install if a dependency is missing
* Skips corrupt or unsupported files gracefully instead of crashing
* Supports JPG, JPEG, PNG, WEBP, TIFF, BMP input formats
* All HDR metadata parameters are configurable at the top of the script

## **How It Works**

### Gainmap Generation
The script generates a synthetic gainmap from the SDR source image using FFmpeg. The image is run through `gradfun` to suppress banding artifacts, then a fixed tone curve is applied that darkens the midtones slightly (`0/0 0.50/0.95 1/1`). The result is output as a 48-bit grayscale image for use as the gainmap. The same fixed curve is applied to every image regardless of its content.

### Ultra HDR Assembly
The SDR base image and gainmap are passed to `ultrahdr_app`, which combines them into a single JPEG file conforming to the [Ultra HDR specification](https://developer.android.com/media/platform/hdr-image-format). The gainmap is embedded as metadata inside the JPEG, making the output fully backwards compatible software that does not understand Ultra HDR will simply display the SDR base image.

### Non-JPG Handling
Images that are not already JPEG are composited over a solid black background before processing. This handles transparency in formats like PNG correctly, as the Ultra HDR format requires a JPEG base image.

### Auto-Build
If `ultrahdr_app` is not found next to the script, it clones [libultrahdr](https://github.com/google/libultrahdr) into a temporary directory, builds it with CMake, copies the binary to the script's directory and cleans up the build files automatically.

## **Metadata Settings**

The following values are defined at the top of the script and written to `metadata.cfg` on every run.

| Variable | Default | Description |
|---|---|---|
| `MAX_CONTENT_BOOST` | 6.25 | Max brightness multiplier on HDR displays (6.25 = 625% peak) |
| `MIN_CONTENT_BOOST` | 1.0 | Min brightness multiplier (1.0 = no boost floor) |
| `GAMMA` | 1.0 | Gainmap gamma curve (1.0 = linear) |
| `OFFSET_SDR` | 0.015625 | SDR noise floor offset (1/64, prevents divide-by-zero) |
| `OFFSET_HDR` | 0.015625 | HDR noise floor offset (1/64, prevents divide-by-zero) |
| `HDR_CAPACITY_MIN` | 1.0 | Minimum HDR headroom |
| `HDR_CAPACITY_MAX` | 6.25 | Maximum HDR headroom (should match `MAX_CONTENT_BOOST`) |
| `USE_BASE_COLOR_SPACE` | 1 | 1 = gainmap in SDR color space, 0 = HDR color space |

## **Usage**

```bash
# Single image
./fake-hdr.sh image.png

# Entire directory (outputs to directory/HDR/)
./fake-hdr.sh /path/to/images/
```

## **Dependencies**

* `ffmpeg`
* `cmake`
* `make` / `base-devel`
* `git`
* `libjpeg-turbo` (Arch) / `libjpeg-dev` (Debian) / `libjpeg-turbo-devel` (Fedora)
