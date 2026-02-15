import Foundation

struct SkyboxCatalog {
    static let builtinNames: [String] = [
        "2", "13", "15", "23", "i", "11", "5", "16", 
        "22", "f", "a", "25", "17", "d", "t", "21", "8", "7", "1", 
        "26", "3", "cobblestone1", "outpost", 
        "street1", "santorini1", "terrace1"
    ]
    
    static let rotations: [String: Float] = [
        "3": Float(530.0 * .pi / 180.0),
        "5": -2.478,
        "8": Float(115.0 * .pi / 180.0),
        "11": 0.175,
        "15": -0.105,
        "16": Float(-50.0 * .pi / 180.0),
        "17": 1.867,
        "21": -1.921,
        "23": -2.007,
        "26": -0.524,
        "a": Float(150.0 * .pi / 180.0),
        "b": Float(145.0 * .pi / 180.0),
        "c": Float(125.0 * .pi / 180.0),
        "d": Float(-280.0 * .pi / 180.0),
        "f": Float(5.0 * .pi / 180.0),
        "i": Float(-90.0 * .pi / 180.0),
        "w": Float(-160.0 * .pi / 180.0),
        "y": Float(-15.0 * .pi / 180.0),
        "cobblestone1": Float(156.0 * .pi / 180.0),
        "outpost": Float(-8.0 * .pi / 180.0),
        "street1": Float(175.0 * .pi / 180.0),
        "santorini1": Float(280.0 * .pi / 180.0),
        "terrace1": Float(28.0 * .pi / 180.0)
    ]
    
    static let displayNames: [String: String] = [
        "1": "Loft",
        "2": "Moonlight",
        "3": "Full Moon",
        "5": "Moondaze",    
        "7": "Trackday",
        "8": "Atlantis",
        "11": "Inked",
        "13": "Jungle",
        "15": "Monolith",
        "16": "Meadow",
        "17": "Fireflies",
        "21": "Reach",
        "22": "Mistfire",
        "23": "Apocalypse",
        "25": "Rubble",
        "26": "Zenith",
        "a": "Metro",
        "b": "Stalked",
        "c": "Stalked",
        "d": "Stalked",
        "f": "Foundry",
        "i": "Station",
        "t": "Moonrise",
        "w": "NeoCity",
        "x": "Arc",
        "y": "Arc",
        "cobblestone1": "Cobblestone",
        "outpost": "Arc",
        "street1": "Oasis",
        "santorini1": "Realm",
        "terrace1": "Nexus"
    ]
    
    static let newsetNames: [String] = [
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
        "k", "l", "m", "n", "o", "p", "q", "r", "s", "t",
        "u", "v", "w", "x", "y", "z"
    ]
    
    static let newsetRotations: [String: Float] = [
        "a": Float(150.0 * .pi / 180.0),
        "b": Float(180.0 * .pi / 180.0),
        "c": Float(15.0 * .pi / 180.0),
        "d": Float(-160.0 * .pi / 180.0),
        "e": Float(-90.0 * .pi / 180.0),
        "f": Float(5.0 * .pi / 180.0),
        "g": Float(-100.0 * .pi / 180.0),
        "h": Float(-100.0 * .pi / 180.0),
        "i": Float(-90.0 * .pi / 180.0),
        "j": Float(-10.0 * .pi / 180.0),
        "k": Float(115.0 * .pi / 180.0),
        "l": Float(-50.0 * .pi / 180.0),
        "n": Float(30.0 * .pi / 180.0),
        "u": Float(180.0 * .pi / 180.0),
        "z": Float(20.0 * .pi / 180.0)
    ]
}
