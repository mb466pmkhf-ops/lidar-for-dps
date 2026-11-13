import Foundation

// Known quirks of each fixture type and recording format: practical things a crew should know when
// planning with them (flicker, warm-up, power, frame-rate limits, lens coverage…). Every quirk names
// its source. "General crew practice" marks well-known behaviour with no single published figure;
// "How FrameScan models it" explains the app's own calculation. Figures elsewhere come from the
// maker's published data and can change with software and licences.
// web/src/model/quirks.ts holds the same table; CI compares the two (photometry-audit.test.ts).

struct UnitQuirk: Hashable {
    var text: String
    var source: String
    var url: String? = nil
}

enum KnownQuirks {
    static func fixture(_ id: String) -> [UnitQuirk] { fixtures[id] ?? [] }
    static func sensor(_ id: String) -> [UnitQuirk] { sensors[id] ?? [] }

    // MARK: Lights
    private static let dimmedLedsCanFlicker = UnitQuirk(text: "Dimmed LEDs can flicker on camera at high frame rates or unusual shutter angles. Use the unit's high-speed or flicker-free mode and test on camera.",
        source: "Flicker-free dimming explainer", url: "https://www.waveformlighting.com/film-photography/an-introduction-to-flicker-free-led-strip-dimming")
    private static let fanCooledQuietOr = UnitQuirk(text: "Fan-cooled. Quiet or passive fan modes usually cap the output, so check which mode you'll need for sound takes before relying on full output.",
        source: "General crew practice")
    private static let theOutputFigureIs = UnitQuirk(text: "The output figure is with the standard 55° reflector. Bare, the COB spreads wide and loses most of its throw.",
        source: "How FrameScan models it")
    private static let allTheLightComes = UnitQuirk(text: "All the light comes from one small, very bright chip: hard shadows and uncomfortable to look into. Diffuse or bounce it near faces.",
        source: "General crew practice")
    private static let atFullOutputIt = UnitQuirk(text: "At full output it draws about 10 A at 120 V, which is most of a 15 A household circuit. Give it its own circuit.",
        source: "Electrical: current = watts ÷ volts")
    private static let biColourUnitsMix = UnitQuirk(text: "Bi-colour units mix warm and cool LEDs, so output is usually highest mid-range and drops toward the warm and cool ends. The figure here is at 5600 K.",
        source: "US DOE: colour-tunable LEDs", url: "https://www.energy.gov/eere/ssl/understanding-led-color-tunable-products")
    private static let mixedWhitesCanDrift = UnitQuirk(text: "Mixed whites can drift slightly green or magenta, especially dimmed very low. Check skin with a colour meter and correct with minus or plus green.",
        source: "US DOE: colour-tunable LEDs", url: "https://www.energy.gov/eere/ssl/understanding-led-color-tunable-products")
    private static let saturatedColoursGiveFar = UnitQuirk(text: "Saturated colours give far less light than white; deep blue can be under a tenth. FrameScan already scales the output for the colour you pick.",
        source: "How FrameScan models it")
    private static let unitsWithOnlyRed = UnitQuirk(text: "Units with only red, green and blue emitters render skin poorly in white. Units that add white emitters (RGBW, RGBWW) do much better.",
        source: "Broadcast Bridge: LEDs for better or worse", url: "https://www.thebroadcastbridge.com/content/entry/14660/hdr-part-7-leds-for-better-for-worse")
    private static let theOutputFigureIs2 = UnitQuirk(text: "The output figure is at full flood. Spotting in concentrates the beam but the lens catches less of the light; FrameScan models that loss.",
        source: "How FrameScan models it")
    private static let aFresnelSSoft = UnitQuirk(text: "A fresnel's soft-edged beam takes barn doors and flags cleanly, which makes it easier to shape than a COB with a reflector.",
        source: "General crew practice")
    private static let barePanelsAreMade = UnitQuirk(text: "Bare panels are made of many small emitters and can throw multiple shadows up close. Add diffusion or a softbox for faces.",
        source: "General crew practice")
    private static let barnDoorsOnA = UnitQuirk(text: "Barn doors on a panel trim spill but can't make the hard cut a fresnel can.",
        source: "General crew practice")
    private static let aFlexibleMatNeeds = UnitQuirk(text: "A flexible mat needs its frame and diffusion. Without the diffusion it looks spotty; the output figure here includes it.",
        source: "How FrameScan models it")
    private static let theDriverIsUsually = UnitQuirk(text: "The driver is usually a separate box on a cable, and a large frame catches wind outdoors: sandbag the stand and keep a hand on it.",
        source: "General crew practice")
    private static let batteryRunTimeIs = UnitQuirk(text: "Battery run time is shortest at full output. Plan mains power or spare tubes for long setups.",
        source: "General crew practice")
    private static let framescanTreatsTheTube = UnitQuirk(text: "FrameScan treats the tube as lighting all the way round. Many real tubes are brighter on one side or are shaded on the back.",
        source: "How FrameScan models it")
    private static let takesAFewMinutes = UnitQuirk(text: "Takes a few minutes after striking to reach full output and the right colour. Strike it well before the take.",
        source: "Venture Lighting HID FAQ", url: "https://www.venturelighting.com/ws/documents/catalogs/hid-faq.pdf")
    private static let mostHeadsCanT = UnitQuirk(text: "Most heads can't restrike while hot: if it goes out, wait for it to cool unless the lamp and ballast are rated for hot restrike.",
        source: "Wikipedia: HMI light", url: "https://en.wikipedia.org/wiki/HMI_light")
    private static let dimsOnlyToAbout = UnitQuirk(text: "Dims only to about half (one stop) and goes roughly 200 K bluer when dimmed. Use scrims, ND or distance below that.",
        source: "Wikipedia: HMI light", url: "https://en.wikipedia.org/wiki/HMI_light")
    private static let useAnElectronicBallast = UnitQuirk(text: "Use an electronic ballast in flicker-free mode; magnetic ballasts flicker on camera. Quiet ballast modes may only be safe at normal frame rates.",
        source: "Wikipedia: HMI light", url: "https://en.wikipedia.org/wiki/HMI_light")
    private static let emitsUvNeverRun = UnitQuirk(text: "Emits UV: never run it without its lens or UV glass, and replace cracked glass before use.",
        source: "Wikipedia: HMI light", url: "https://en.wikipedia.org/wiki/HMI_light")
    private static let colourTemperatureDriftsWith = UnitQuirk(text: "Colour temperature drifts with lamp age, so meter each head rather than assuming 5600 K.",
        source: "Wikipedia: HMI light", url: "https://en.wikipedia.org/wiki/HMI_light")
    private static let theLampAloneDraws = UnitQuirk(text: "The lamp alone draws 15 A at 120 V (8 A at 230 V), so use a 20 A circuit in 120 V countries. About the largest HMI that runs from a household outlet.",
        source: "Electrical: current = watts ÷ volts")
    private static let tooMuchForA = UnitQuirk(text: "Too much for a household socket: about 17 A at 230 V and over 33 A at 120 V before ballast losses. Plan a generator or a heavy-duty distro circuit.",
        source: "Electrical: current = watts ÷ volts")
    private static let warmsAsItDims = UnitQuirk(text: "Warms as it dims: at half output it is about 250 K warmer. FrameScan models this.",
        source: "How FrameScan models it")
    private static let fullCtbToMatch = UnitQuirk(text: "Full CTB to match daylight passes only about 36 % (1½ stops), so a tungsten unit makes a weak daylight source.",
        source: "LEE 201 Full CTB datasheet")
    private static let runsVeryHotClip = UnitQuirk(text: "Runs very hot. Clip gels to the barn doors' gel frame, not the lens, and keep set dressing and drapes clear.",
        source: "General crew practice")
    private static let silentNoFanAnd = UnitQuirk(text: "Silent (no fan) and dims smoothly on a standard tungsten dimmer, which makes it easy to use for sound and for practical effects.",
        source: "General crew practice")
    private static let drawsAbout8A = UnitQuirk(text: "Draws about 8 A at 120 V or 4 A at 230 V; two will share a 20 A circuit at 120 V.",
        source: "Electrical: current = watts ÷ volts")
    private static let drawsAbout17A = UnitQuirk(text: "Draws about 17 A at 120 V, more than a standard 15 A household circuit; about 9 A at 230 V.",
        source: "Electrical: current = watts ÷ volts")
    private static let lightsEverythingAroundIt = UnitQuirk(text: "Lights everything around it, ceiling and walls included. Use a skirt to stop spill and keep contrast.",
        source: "General crew practice")
    private static let framescanTreatsTheLantern = UnitQuirk(text: "FrameScan treats the lantern as an even sphere; a skirt or half-skirt isn't modelled yet.",
        source: "How FrameScan models it")
    private static let householdLedBulbsOften = UnitQuirk(text: "Household LED bulbs often flicker on camera, especially on dimmers or at high frame rates. Test them, or swap for flicker-free film bulbs.",
        source: "Flicker-free dimming explainer", url: "https://www.waveformlighting.com/film-photography/an-introduction-to-flicker-free-led-strip-dimming")
    private static let manyArenTDimmable = UnitQuirk(text: "Many aren't dimmable on an ordinary dimmer, and colour rendering is often only fair. Check the packaging before you rely on one.",
        source: "General crew practice")
    private static let about2800K = UnitQuirk(text: "About 2,800 K bare and warms further when dimmed, so it reads warmer than a 3200 K tungsten film light.",
        source: "How FrameScan models it")
    private static let q100WHouseholdTungsten = UnitQuirk(text: "100 W household tungsten bulbs are no longer sold in the EU and UK. Source them from film suppliers or use a dimmed photoflood.",
        source: "EU Regulation 244/2009", url: "https://eur-lex.europa.eu/eli/reg/2009/244/oj")

    static let fixtures: [String: [UnitQuirk]] = [
        "cob-100-bi": [dimmedLedsCanFlicker, theOutputFigureIs, allTheLightComes, biColourUnitsMix, mixedWhitesCanDrift],
        "cob-300-bi": [dimmedLedsCanFlicker, fanCooledQuietOr, theOutputFigureIs, allTheLightComes, biColourUnitsMix, mixedWhitesCanDrift],
        "cob-300-d": [dimmedLedsCanFlicker, fanCooledQuietOr, theOutputFigureIs, allTheLightComes],
        "cob-600-bi": [dimmedLedsCanFlicker, fanCooledQuietOr, theOutputFigureIs, allTheLightComes, biColourUnitsMix, mixedWhitesCanDrift],
        "cob-600-d": [dimmedLedsCanFlicker, fanCooledQuietOr, theOutputFigureIs, allTheLightComes],
        "cob-1200-d": [dimmedLedsCanFlicker, fanCooledQuietOr, theOutputFigureIs, allTheLightComes, atFullOutputIt],
        "fresnel-led-200-bi": [dimmedLedsCanFlicker, fanCooledQuietOr, biColourUnitsMix, mixedWhitesCanDrift, theOutputFigureIs2, aFresnelSSoft],
        "fresnel-led-600-d": [dimmedLedsCanFlicker, fanCooledQuietOr, theOutputFigureIs2, aFresnelSSoft],
        "panel-1x1-bi": [dimmedLedsCanFlicker, biColourUnitsMix, mixedWhitesCanDrift, barePanelsAreMade, barnDoorsOnA],
        "panel-1x1-rgb": [dimmedLedsCanFlicker, saturatedColoursGiveFar, unitsWithOnlyRed, barePanelsAreMade, barnDoorsOnA],
        "panel-2x1-bi": [dimmedLedsCanFlicker, biColourUnitsMix, mixedWhitesCanDrift, barePanelsAreMade, barnDoorsOnA],
        "panel-2x1-rgb": [dimmedLedsCanFlicker, saturatedColoursGiveFar, unitsWithOnlyRed, barePanelsAreMade, barnDoorsOnA],
        "tube-2ft-rgb": [dimmedLedsCanFlicker, saturatedColoursGiveFar, unitsWithOnlyRed, batteryRunTimeIs, framescanTreatsTheTube],
        "tube-4ft-rgb": [dimmedLedsCanFlicker, saturatedColoursGiveFar, unitsWithOnlyRed, batteryRunTimeIs, framescanTreatsTheTube],
        "mat-2x2-bi": [dimmedLedsCanFlicker, biColourUnitsMix, mixedWhitesCanDrift, aFlexibleMatNeeds, theDriverIsUsually],
        "mat-4x4-bi": [dimmedLedsCanFlicker, biColourUnitsMix, mixedWhitesCanDrift, aFlexibleMatNeeds, theDriverIsUsually],
        "hmi-1800-par": [takesAFewMinutes, mostHeadsCanT, dimsOnlyToAbout, useAnElectronicBallast, emitsUvNeverRun, colourTemperatureDriftsWith, theLampAloneDraws],
        "hmi-4000-par": [takesAFewMinutes, mostHeadsCanT, dimsOnlyToAbout, useAnElectronicBallast, emitsUvNeverRun, colourTemperatureDriftsWith, tooMuchForA],
        "tungsten-650": [warmsAsItDims, fullCtbToMatch, runsVeryHotClip, silentNoFanAnd],
        "tungsten-1k": [warmsAsItDims, fullCtbToMatch, runsVeryHotClip, silentNoFanAnd, drawsAbout8A],
        "tungsten-2k": [warmsAsItDims, fullCtbToMatch, runsVeryHotClip, silentNoFanAnd, drawsAbout17A],
        "lantern-300-bi": [dimmedLedsCanFlicker, fanCooledQuietOr, biColourUnitsMix, mixedWhitesCanDrift, lightsEverythingAroundIt, framescanTreatsTheLantern],
        "bulb-led-60": [householdLedBulbsOften, manyArenTDimmable],
        "bulb-tungsten-100": [about2800K, q100WHouseholdTungsten],
    ]

    // MARK: Cameras
    private static let upTo40Fps = UnitQuirk(text: "Up to 40 fps in this mode (ARRIRAW or ProRes). Rates can change with software and licences.",
        source: "ARRI Mini LF recording formats", url: "https://www.arri.com/resource/blob/306446/d7bf94ecd6bc57c4b430b360b7cdc7e6/alexa-mini-lf-recording-formats-sheet-din-a4-size-pdf-data.pdf")
    private static let needsA4471 = UnitQuirk(text: "Needs a 44.71 mm image circle: only true large-format lenses cover it without vignetting.",
        source: "ARRI Alexa Mini LF", url: "https://www.arri.com/alexaminilf")
    private static let builtInNdFilters = UnitQuirk(text: "Built-in ND filters, LPL mount (PL with the adapter).",
        source: "ARRI Alexa Mini LF", url: "https://www.arri.com/alexaminilf")
    private static let upTo60Fps = UnitQuirk(text: "Up to 60 fps in 3.8K UHD; the larger 4.3K 16:9 mode (35.64 × 20.05 mm) is ProRes only and stops at 48 fps. Rates can change with software and licences.",
        source: "ARRI Mini LF recording formats", url: "https://www.arri.com/resource/blob/306446/d7bf94ecd6bc57c4b430b360b7cdc7e6/alexa-mini-lf-recording-formats-sheet-din-a4-size-pdf-data.pdf")
    private static let manySuper35Lenses = UnitQuirk(text: "Many Super 35 lenses cover LF 16:9. Check yours with ARRI's lens illumination tool.",
        source: "ARRI Mini LF FAQ", url: "https://arri.com/en/learn-help/learn-help-camera-system/frequently-asked-questions/alexa-mini-lf-faq")
    private static let upTo75Fps = UnitQuirk(text: "Up to 75 fps ARRIRAW on a 2 TB drive (35 fps on 1 TB), 60 fps ProRes. Rates can change with software and licences.",
        source: "ARRI Alexa 35 format poster", url: "https://www.arri.com/resource/blob/296424/88454a5a3dee9fe1d3fd68e75aa3411e/alexa-35-recording-format-poster-data.pdf")
    private static let needsA3396 = UnitQuirk(text: "Needs a 33.96 mm image circle, larger than classic Super 35: check lens coverage.",
        source: "ARRI Alexa 35 format poster", url: "https://www.arri.com/resource/blob/296424/88454a5a3dee9fe1d3fd68e75aa3411e/alexa-35-recording-format-poster-data.pdf")
    private static let openGateNeedsArri = UnitQuirk(text: "Open Gate needs ARRI's Open Gate / anamorphic licence on cameras that don't include it.",
        source: "ARRI Alexa 35", url: "https://arri.com/en/camera-systems/cameras/alexa-35")
    private static let upTo120Fps = UnitQuirk(text: "Up to 120 fps ARRIRAW on a 2 TB drive (55 on 1 TB), 100 fps ProRes, with the high-speed licence. Rates can change with software and licences.",
        source: "ARRI Alexa 35 format poster", url: "https://www.arri.com/resource/blob/296424/88454a5a3dee9fe1d3fd68e75aa3411e/alexa-35-recording-format-poster-data.pdf")
    private static let q2855MmImage = UnitQuirk(text: "28.55 mm image circle: classic Super 35 lenses cover it.",
        source: "ARRI Alexa 35 format poster", url: "https://www.arri.com/resource/blob/296424/88454a5a3dee9fe1d3fd68e75aa3411e/alexa-35-recording-format-poster-data.pdf")
    private static let openGateRecordsArriraw = UnitQuirk(text: "Open Gate records ARRIRAW only.",
        source: "ARRI Alexa Mini recording areas", url: "https://www.arri.com/resource/blob/178064/d84031615b6bf09446aeb7972066b129/alexa-mini-recording-areas-surround-views-and-framelines-sup-4-0-data.pdf")
    private static let needsA3359 = UnitQuirk(text: "Needs a 33.59 mm image circle, more than standard Super 35 lenses are designed for.",
        source: "ARRI Alexa Mini recording areas", url: "https://www.arri.com/resource/blob/178064/d84031615b6bf09446aeb7972066b129/alexa-mini-recording-areas-surround-views-and-framelines-sup-4-0-data.pdf")
    private static let forHighSpeedThe = UnitQuirk(text: "For high speed the Mini drops to smaller modes (up to 200 fps in 2.8K 16:9).",
        source: "ARRI Mini LF FAQ", url: "https://arri.com/en/learn-help/learn-help-camera-system/frequently-asked-questions/alexa-mini-lf-faq")
    private static let upTo30Fps = UnitQuirk(text: "Up to 30 fps in 8.6K 3:2; 8.6K 17:9 reaches 48 fps and 8.2K 17:9 60 fps. Rates can change with software and licences.",
        source: "Sony Venice 2 recording formats", url: "https://77snszqv.media.zestyio.com/Sony_VENICE2_RecordingFormats.pdf")
    private static let needsA432 = UnitQuirk(text: "Needs a 43.2 mm image circle: use large-format lenses.",
        source: "Sony Venice 2 recording formats", url: "https://77snszqv.media.zestyio.com/Sony_VENICE2_RecordingFormats.pdf")
    private static let builtIn8Step = UnitQuirk(text: "Built-in 8-step ND (0.3 to 2.4). PL mount, or E-mount with the lens lock removed.",
        source: "Sony Venice 2", url: "https://pro.sony/en_AU/products/digital-cinema-cameras/venice2")
    private static let upTo30Fps2 = UnitQuirk(text: "Up to 30 fps as standard; 72 fps needs the high frame rate licence. Rates can change with software and licences.",
        source: "Sony Venice", url: "https://pro.sony/ue_US/pro/product/venice")
    private static let fullFrameModesNeed = UnitQuirk(text: "Full-frame modes need the full frame licence on the original Venice.",
        source: "Sony Venice", url: "https://pro.sony/ue_US/pro/product/venice")
    private static let upTo60Fps2 = UnitQuirk(text: "Up to 60 fps as standard, 110 fps with the high frame rate licence. Rates can change with software and licences.",
        source: "Sony Venice", url: "https://pro.sony/ue_US/pro/product/venice")
    private static let thisModeIsOn = UnitQuirk(text: "This mode is on the original Venice (and the Venice 2 6K sensor). The Venice 2 8K sensor's Super 35 modes start at 5.4K.",
        source: "Sony Venice 2 format chart", url: "https://www.sony.jp/ls-camera/reference/pdf/VENICE_2_MPC-3628_recording_format.pdf")
    private static let theFx6HasA = UnitQuirk(text: "The FX6 has a built-in electronic variable ND; the FX3 has no internal ND, so plan screw-in or matte-box ND.",
        source: "Sony FX6", url: "https://pro.sony/ue_US/products/handheld-camcorders/ilme-fx6v")
    private static let bothRecord4kUp = UnitQuirk(text: "Both record 4K up to 120 fps internally.",
        source: "Sony FX3 specifications", url: "https://www.sony-mea.com/en/electronics/interchangeable-lens-cameras/ilme-fx3a/specifications")
    private static let eMountSonyPublishes = UnitQuirk(text: "E-mount. Sony publishes the sensor as 35.6 × 23.8 mm; this preset is its full-width 16:9 area.",
        source: "Sony FX3 specifications", url: "https://www.sony-mea.com/en/electronics/interchangeable-lens-cameras/ilme-fx3a/specifications")
    private static let upTo120Fps2 = UnitQuirk(text: "Up to 120 fps at 8K 17:9 (150 fps at 2.4:1). Rates can change with software and licences.",
        source: "RED V-Raptor", url: "https://www.red.com/v-raptor_4")
    private static let theOriginalVRaptor = UnitQuirk(text: "The original V-Raptor has a rolling shutter; the V-Raptor [X] models are global shutter.",
        source: "RED V-Raptor", url: "https://www.red.com/v-raptor_4")
    private static let q4631MmImage = UnitQuirk(text: "46.31 mm image circle: use VV / large-format lenses. RF mount, PL with an adapter.",
        source: "RED V-Raptor", url: "https://www.red.com/v-raptor_4")
    private static let a6kWindowOf = UnitQuirk(text: "A 6K window of the 8K VV sensor: up to 160 fps at 17:9 (200 fps at 2.4:1). Rates can change with software and licences.",
        source: "RED V-Raptor", url: "https://www.red.com/v-raptor_4")
    private static let widerThanClassicSuper = UnitQuirk(text: "Wider than classic Super 35 (30.7 mm): some S35 lenses vignette in the corners.",
        source: "General crew practice")
    private static let rfMountPlWith = UnitQuirk(text: "RF mount, PL with an adapter.",
        source: "RED V-Raptor", url: "https://www.red.com/v-raptor_4")
    private static let globalShutterNoRolling = UnitQuirk(text: "Global shutter: no rolling-shutter skew on whip pans or flashing lights.",
        source: "RED Komodo 6K tech specs", url: "https://docs.red.com/955-0196_v1.6/Content/A_TechSpecs/Specs_KOMODO_6K.htm")
    private static let q6k179Stops = UnitQuirk(text: "6K 17:9 stops at 40 fps; drop to 4K for 60 fps or 2K for 120 fps. Rates can change with software and licences.",
        source: "RED Komodo 6K tech specs", url: "https://docs.red.com/955-0196_v1.6/Content/A_TechSpecs/Specs_KOMODO_6K.htm")
    private static let noBuiltInNd = UnitQuirk(text: "No built-in ND. RF mount; ND needs filters or an electronic-ND lens adapter.",
        source: "RED Komodo 6K tech specs", url: "https://docs.red.com/955-0196_v1.6/Content/A_TechSpecs/Specs_KOMODO_6K.htm")
    private static let super35LensesOnly = UnitQuirk(text: "Super 35 lenses only cover the centre of a full-frame sensor; expect vignetting unless you crop.",
        source: "Wikipedia: full-frame sensor", url: "https://en.wikipedia.org/wiki/Full-frame_digital_SLR")
    private static let theFullSilentAperture = UnitQuirk(text: "The full silent aperture: about 32 % more area than 35 mm Academy.",
        source: "Wikipedia: Super 35", url: "https://en.wikipedia.org/wiki/Super_35")
    private static let mostAnamorphic2Lenses = UnitQuirk(text: "Most anamorphic 2× lenses are designed for this 4-perf frame height.",
        source: "General crew practice")
    private static let a169Crop = UnitQuirk(text: "A 16:9 crop of the Super 35 width; the height is derived from the 24.89 mm width.",
        source: "Wikipedia: Super 35", url: "https://en.wikipedia.org/wiki/Super_35")
    private static let cropFactor20 = UnitQuirk(text: "Crop factor 2.0 against full frame: a 25 mm lens frames like a 50 mm on full frame.",
        source: "Wikipedia: Micro Four Thirds", url: "https://en.wikipedia.org/wiki/Micro_Four_Thirds_system")
    private static let videoModesRecordA = UnitQuirk(text: "Video modes record a 16:9 or 17:9 crop of this 4:3 area, so the real frame is a little shorter.",
        source: "Wikipedia: Micro Four Thirds", url: "https://en.wikipedia.org/wiki/Micro_Four_Thirds_system")
    private static let needsSuper16Lenses = UnitQuirk(text: "Needs Super 16 lenses: standard 16 mm lenses can vignette on the wider frame.",
        source: "Wikipedia: Super 16", url: "https://en.wikipedia.org/wiki/Super_16_mm_film")
    private static let nativeAspectAbout1 = UnitQuirk(text: "Native aspect about 1.69:1 (12.52 × 7.41 mm), close to 16:9.",
        source: "Wikipedia: Super 16", url: "https://en.wikipedia.org/wiki/Super_16_mm_film")

    private static let pitchArri35 = UnitQuirk(text: "Size worked out from ARRI's 6.075 µm photosite pitch and the mode's photosite count. Check the format chart before a lens test.",
        source: "How FrameScan models it")
    private static let pitchArriLf = UnitQuirk(text: "Size worked out from ARRI's 8.25 µm photosite pitch and the mode's photosite count. Check the format chart before a lens test.",
        source: "How FrameScan models it")
    private static let sixFiveFor2x = UnitQuirk(text: "A 6:5 area made for 2× anamorphic: desqueezed it is about 2.4:1.",
        source: "General crew practice")
    private static let fourThreeFor2x = UnitQuirk(text: "A 4:3 area for 2× anamorphic: desqueezed it is about 2.67:1, usually cropped to 2.39:1.",
        source: "General crew practice")
    private static let lfWidthAt239 = UnitQuirk(text: "Full LF width with a 2.39:1 height: large-format lenses still needed for the width.",
        source: "General crew practice")
    private static let needs65Lenses = UnitQuirk(text: "59.9 mm diagonal: full-frame and LF lenses vignette here, so plan 65 mm-format lenses.",
        source: "How FrameScan models it")
    private static let windowedModes = UnitQuirk(text: "Lower resolutions can window the sensor and frame tighter. Check the recording mode before trusting the lines.",
        source: "General crew practice")
    private static let c70SharesSensor = UnitQuirk(text: "The C70 uses the same Super 35 sensor as the C300 Mark III.",
        source: "General crew practice")
    private static let redS35Spec = UnitQuirk(text: "26.21 × 13.82 mm, 8192 × 4320 photosites. Classic Super 35 lenses cover it.",
        source: "RED V-Raptor 8K S35 tech specs", url: "https://docs.red.com/955-0215/955-0215_V1.4_Rev-B%20RED%20PS,%20V-RAPTOR%208K%20S35%20Operation%20Guide/Content/C_TechSpecs/Specs_V-RAPTOR.htm")
    private static let venice86k179 = UnitQuirk(text: "8640 × 4556 photosites; needs a 40.63 mm image circle.",
        source: "Sony Venice 2 recording formats", url: "https://77snszqv.media.zestyio.com/Sony_VENICE2_RecordingFormats.pdf")
    private static let venice82k239 = UnitQuirk(text: "8192 × 3432 photosites; needs a 36.95 mm image circle.",
        source: "Sony Venice 2 recording formats", url: "https://77snszqv.media.zestyio.com/Sony_VENICE2_RecordingFormats.pdf")
    private static let venice58k65 = UnitQuirk(text: "5792 × 4854 photosites, made for 2× anamorphic; needs a 31.44 mm image circle.",
        source: "Sony Venice 2 recording formats", url: "https://77snszqv.media.zestyio.com/Sony_VENICE2_RecordingFormats.pdf")
    private static let venice58k43 = UnitQuirk(text: "5792 × 4276 photosites; needs a 29.95 mm image circle.",
        source: "Sony Venice 2 recording formats", url: "https://77snszqv.media.zestyio.com/Sony_VENICE2_RecordingFormats.pdf")
    private static let threePerf = UnitQuirk(text: "3-perf pulls down three perforations a frame: about 1.78:1 and a quarter less film than 4-perf.",
        source: "Wikipedia: 3-perf", url: "https://en.wikipedia.org/wiki/3-perf")
    private static let academyAperture = UnitQuirk(text: "The Academy camera aperture, 0.864 × 0.630 in: the classic 1.37:1 frame.",
        source: "Wikipedia: Academy ratio", url: "https://en.wikipedia.org/wiki/Academy_ratio")
    private static let fivePerf65 = UnitQuirk(text: "5-perf 65 mm camera aperture, about 2.2:1.",
        source: "Wikipedia: 70 mm film", url: "https://en.wikipedia.org/wiki/70_mm_film")
    private static let imax1570 = UnitQuirk(text: "15-perf 65 mm runs sideways through the camera: about 1.43:1.",
        source: "Wikipedia: IMAX", url: "https://en.wikipedia.org/wiki/IMAX")
    private static let standard16 = UnitQuirk(text: "Standard 16 camera aperture, about 1.37:1. Super 16 is wider on the same film.",
        source: "Wikipedia: 16 mm film", url: "https://en.wikipedia.org/wiki/16_mm_film")

    static let sensors: [String: [UnitQuirk]] = [
        "arri-35-og": [upTo75Fps, needsA3396, openGateNeedsArri],
        "arri-35-169": [upTo120Fps, q2855MmImage],
        "arri-minilf-og": [upTo40Fps, needsA4471, builtInNdFilters],
        "arri-minilf-169": [upTo60Fps, manySuper35Lenses, builtInNdFilters],
        "arri-mini-og": [openGateRecordsArriraw, needsA3359, forHighSpeedThe],
        "red-vraptor-8k-vv": [upTo120Fps2, theOriginalVRaptor, q4631MmImage],
        "red-vraptor-6k-s35": [a6kWindowOf, widerThanClassicSuper, rfMountPlWith],
        "red-komodo-6k": [globalShutterNoRolling, q6k179Stops, noBuiltInNd],
        "sony-venice2-86k": [upTo30Fps, needsA432, builtIn8Step],
        "sony-venice-6k-179": [upTo30Fps2, fullFrameModesNeed, builtIn8Step],
        "sony-venice-4k-s35": [upTo60Fps2, thisModeIsOn],
        "sony-fx6": [theFx6HasA, bothRecord4kUp, eMountSonyPublishes],
        "generic-ff": [super35LensesOnly],
        "generic-s35-4perf": [theFullSilentAperture, mostAnamorphic2Lenses],
        "generic-s35-169": [a169Crop],
        "generic-m43": [cropFactor20, videoModesRecordA],
        "generic-s16": [needsSuper16Lenses, nativeAspectAbout1],
        "arri-35-46-169": [pitchArri35],
        "arri-35-65": [pitchArri35, sixFiveFor2x],
        "arri-minilf-239": [pitchArriLf, lfWidthAt239],
        "arri-65-og": [pitchArriLf, needs65Lenses],
        "arri-mini-32k": [pitchArriLf],
        "arri-mini-43": [pitchArriLf, fourThreeFor2x],
        "bmd-ursacine-12k": [windowedModes],
        "bmd-ursa-12k": [windowedModes],
        "bmd-pocket-6k": [windowedModes],
        "bmd-pocket-4k": [windowedModes],
        "canon-c500-2": [windowedModes],
        "canon-c300-3": [c70SharesSensor, windowedModes],
        "red-vraptor-8k-s35": [redS35Spec],
        "sony-venice2-86k-179": [venice86k179],
        "sony-venice2-82k-239": [venice82k239],
        "sony-venice2-58k-65": [venice58k65, sixFiveFor2x],
        "sony-venice2-58k-43": [venice58k43, fourThreeFor2x],
        "generic-s35-3perf": [threePerf],
        "generic-academy": [academyAperture],
        "generic-65-5perf": [fivePerf65],
        "generic-imax-1570": [imax1570],
        "generic-16": [standard16],
    ]
}
