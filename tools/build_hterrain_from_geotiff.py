#!/usr/bin/env python3
"""Prepare a georeferenced GeoTIFF as elevation-only HTerrain input.

Run this through the `terrain` Nix shell from godot-cesium-preview so Rasterio
and NumPy are available. A small Godot build script converts the generated
float byte stream into HTerrain's portable `height.res` Image resource.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.windows import from_bounds


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("survey", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("raw_output", type=Path)
    return parser.parse_args()


def main() -> None:
    args = arguments()
    survey = json.loads(args.survey.read_text())
    origin_east, origin_north, origin_altitude = survey["registration"]["source_origin"]
    # Match the old local-tiles builder's robust survey centre, but retain only
    # one HTerrain-supported 4096 m square around it.
    station_east = [origin_east + station["position"][0] for station in survey["stations"]]
    station_north = [origin_north - station["position"][2] for station in survey["stations"]]
    centre_east = statistics.median(station_east)
    centre_north = statistics.median(station_north)
    west = math.floor(centre_east - 2048.0)
    south = math.floor(centre_north - 2048.0)
    east = west + 4096.0
    north = south + 4096.0

    with rasterio.open(args.source) as dataset:
        if dataset.crs is None or dataset.crs.to_epsg() != 32633:
            raise RuntimeError(f"Expected EPSG:32633 terrain, found {dataset.crs}")
        window = from_bounds(west, south, east, north, dataset.transform)
        heights = dataset.read(
            1,
            window=window,
            out_shape=(4096, 4096),
            resampling=Resampling.bilinear,
            masked=True,
        )
        if np.any(heights.mask):
            raise RuntimeError("The requested cave terrain crop contains source NoData")
        heights = np.asarray(heights, dtype=np.float32)
        transform = rasterio.transform.from_bounds(west, south, east, north, 4096, 4096)
        bounds = rasterio.coords.BoundingBox(west, south, east, north)

    if heights.shape == (4096, 4096):
        # WCS pixels are samples at metre cell centres. HTerrain needs one more
        # shared edge sample to form 4096 quads, so repeat the final south/east
        # samples rather than inventing a discontinuity at the boundary.
        heights = np.pad(heights, ((0, 1), (0, 1)), mode="edge")
    if heights.shape != (4097, 4097):
        raise RuntimeError(f"Expected 4096² or 4097² source, found {heights.shape}")

    heights -= np.float32(origin_altitude)
    heights.astype("<f4", copy=False).tofile(args.raw_output)

    # Pixel-centre placement. Survey local X is east and local Z is south.
    first_east = transform.c + transform.a * 0.5
    first_north = transform.f + transform.e * 0.5
    placement = {
        "schema": "tunnelxr-hterrain-1",
        "source": str(args.source),
        "source_crs": "EPSG:32633",
        "attribution": "Land Steiermark / GIS Steiermark, ALS DGM 1 m, CC BY 4.0",
        "resolution": 4097,
        "metres_per_sample": 1.0,
        "position_local": [
            float(first_east - origin_east),
            0.0,
            float(origin_north - first_north),
        ],
        "source_bounds": [bounds.left, bounds.bottom, bounds.right, bounds.top],
        "height_min_local": float(np.nanmin(heights)),
        "height_max_local": float(np.nanmax(heights)),
    }

    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "placement.json").write_text(json.dumps(placement, indent=2) + "\n")
    # Only the height channel is present. The custom shader derives a flat face
    # normal, avoiding 4097² normal, colour and splat textures on the headset.
    maps = [[{"id": 0}], [], [], [], [], [], [], []]
    (args.output / "data.hterrain").write_text(
        json.dumps({"version": "0.11", "maps": maps}, indent=2) + "\n"
    )
    print(
        f"Prepared {heights.shape[1]}x{heights.shape[0]} terrain, "
        f"local heights {placement['height_min_local']:.1f}.."
        f"{placement['height_max_local']:.1f} m at {placement['position_local']}"
    )


if __name__ == "__main__":
    main()
