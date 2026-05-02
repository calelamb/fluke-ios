// One-time generator. Downloads Natural Earth 10m coastline GeoJSON (public
// domain), clips features to the Salish Sea bbox (47.0–49.5°N,
// -124.7 – -122.0°W), normalizes the coordinate format to [[lat, lng], …],
// writes the result to Packages/FlukeUI/Sources/FlukeUI/Resources/Geography/
// salish-sea-coastline.json.
//
// Output JSON shape:
// {
//   "bbox": [47.0, -124.7, 49.5, -122.0],
//   "polygons": [
//     { "name": "coastline", "tier": "shore",
//       "points": [[lat, lng], [lat, lng], ...] },
//     ...
//   ]
// }
//
// Run: swift scripts/bake-salish-sea-coastline.swift

import Foundation

let bbox = (south: 47.0, west: -124.7, north: 49.5, east: -122.0)
let outputPath = "Packages/FlukeUI/Sources/FlukeUI/Resources/Geography/salish-sea-coastline.json"
let geojsonURL = URL(string: "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_coastline.geojson")!

print("[bake] downloading coastline GeoJSON…")
let data = try Data(contentsOf: geojsonURL)
print("[bake] received \(data.count / 1024) KB")

guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let features = json["features"] as? [[String: Any]] else {
    fatalError("Unexpected GeoJSON structure")
}

func intersectsBbox(_ coords: [[Double]]) -> Bool {
    coords.contains { coord in
        let (lng, lat) = (coord[0], coord[1])
        return lat >= bbox.south && lat <= bbox.north &&
               lng >= bbox.west && lng <= bbox.east
    }
}

func clipped(_ coords: [[Double]]) -> [[Double]] {
    coords
        .filter { coord in
            let (lng, lat) = (coord[0], coord[1])
            return lat >= bbox.south && lat <= bbox.north &&
                   lng >= bbox.west && lng <= bbox.east
        }
        .map { [Double]($0.reversed()) }
}

var polygons: [[String: Any]] = []
for feature in features {
    guard let geom = feature["geometry"] as? [String: Any],
          let type = geom["type"] as? String else { continue }

    var lineStrings: [[[Double]]] = []
    if type == "LineString", let coords = geom["coordinates"] as? [[Double]] {
        lineStrings = [coords]
    } else if type == "MultiLineString", let multi = geom["coordinates"] as? [[[Double]]] {
        lineStrings = multi
    }

    for lineString in lineStrings {
        guard intersectsBbox(lineString) else { continue }
        let clippedCoords = clipped(lineString)
        guard clippedCoords.count >= 3 else { continue }
        polygons.append([
            "name": "coastline",
            "tier": "shore",
            "points": clippedCoords
        ])
    }
}

let outputJSON: [String: Any] = [
    "bbox": [bbox.south, bbox.west, bbox.north, bbox.east],
    "polygons": polygons,
]

let outputData = try JSONSerialization.data(
    withJSONObject: outputJSON,
    options: .prettyPrinted
)
try outputData.write(to: URL(fileURLWithPath: outputPath))
print("[bake] wrote \(polygons.count) polygons (\(outputData.count / 1024) KB) → \(outputPath)")
