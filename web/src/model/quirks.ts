// Port of FrameScout/Core/Models/KnownQuirks.swift: practical things to know about each fixture type
// and recording format, each with its source. Keep the two identical; CI compares them.

export interface UnitQuirk { text: string; source: string; url?: string }

const q = (text: string, source: string, url?: string): UnitQuirk => (url ? { text, source, url } : { text, source });

// Lights
const dimmedLedsCanFlicker = q('Dimmed LEDs can flicker on camera at high frame rates or unusual shutter angles. Use the unit\'s high-speed or flicker-free mode and test on camera.',
  'Flicker-free dimming explainer', 'https://www.waveformlighting.com/film-photography/an-introduction-to-flicker-free-led-strip-dimming');
const fanCooledQuietOr = q('Fan-cooled. Quiet or passive fan modes usually cap the output, so check which mode you\'ll need for sound takes before relying on full output.',
  'General crew practice');
const theOutputFigureIs = q('The output figure is with the standard 55° reflector. Bare, the COB spreads wide and loses most of its throw.',
  'How FrameScan models it');
const allTheLightComes = q('All the light comes from one small, very bright chip: hard shadows and uncomfortable to look into. Diffuse or bounce it near faces.',
  'General crew practice');
const atFullOutputIt = q('At full output it draws about 10 A at 120 V, which is most of a 15 A household circuit. Give it its own circuit.',
  'Electrical: current = watts ÷ volts');
const biColourUnitsMix = q('Bi-colour units mix warm and cool LEDs, so output is usually highest mid-range and drops toward the warm and cool ends. The figure here is at 5600 K.',
  'US DOE: colour-tunable LEDs', 'https://www.energy.gov/eere/ssl/understanding-led-color-tunable-products');
const mixedWhitesCanDrift = q('Mixed whites can drift slightly green or magenta, especially dimmed very low. Check skin with a colour meter and correct with minus or plus green.',
  'US DOE: colour-tunable LEDs', 'https://www.energy.gov/eere/ssl/understanding-led-color-tunable-products');
const saturatedColoursGiveFar = q('Saturated colours give far less light than white; deep blue can be under a tenth. FrameScan already scales the output for the colour you pick.',
  'How FrameScan models it');
const unitsWithOnlyRed = q('Units with only red, green and blue emitters render skin poorly in white. Units that add white emitters (RGBW, RGBWW) do much better.',
  'Broadcast Bridge: LEDs for better or worse', 'https://www.thebroadcastbridge.com/content/entry/14660/hdr-part-7-leds-for-better-for-worse');
const theOutputFigureIs2 = q('The output figure is at full flood. Spotting in concentrates the beam but the lens catches less of the light; FrameScan models that loss.',
  'How FrameScan models it');
const aFresnelSSoft = q('A fresnel\'s soft-edged beam takes barn doors and flags cleanly, which makes it easier to shape than a COB with a reflector.',
  'General crew practice');
const barePanelsAreMade = q('Bare panels are made of many small emitters and can throw multiple shadows up close. Add diffusion or a softbox for faces.',
  'General crew practice');
const barnDoorsOnA = q('Barn doors on a panel trim spill but can\'t make the hard cut a fresnel can.',
  'General crew practice');
const aFlexibleMatNeeds = q('A flexible mat needs its frame and diffusion. Without the diffusion it looks spotty; the output figure here includes it.',
  'How FrameScan models it');
const theDriverIsUsually = q('The driver is usually a separate box on a cable, and a large frame catches wind outdoors: sandbag the stand and keep a hand on it.',
  'General crew practice');
const batteryRunTimeIs = q('Battery run time is shortest at full output. Plan mains power or spare tubes for long setups.',
  'General crew practice');
const framescanTreatsTheTube = q('FrameScan treats the tube as lighting all the way round. Many real tubes are brighter on one side or are shaded on the back.',
  'How FrameScan models it');
const takesAFewMinutes = q('Takes a few minutes after striking to reach full output and the right colour. Strike it well before the take.',
  'Venture Lighting HID FAQ', 'https://www.venturelighting.com/ws/documents/catalogs/hid-faq.pdf');
const mostHeadsCanT = q('Most heads can\'t restrike while hot: if it goes out, wait for it to cool unless the lamp and ballast are rated for hot restrike.',
  'Wikipedia: HMI light', 'https://en.wikipedia.org/wiki/HMI_light');
const dimsOnlyToAbout = q('Dims only to about half (one stop) and goes roughly 200 K bluer when dimmed. Use scrims, ND or distance below that.',
  'Wikipedia: HMI light', 'https://en.wikipedia.org/wiki/HMI_light');
const useAnElectronicBallast = q('Use an electronic ballast in flicker-free mode; magnetic ballasts flicker on camera. Quiet ballast modes may only be safe at normal frame rates.',
  'Wikipedia: HMI light', 'https://en.wikipedia.org/wiki/HMI_light');
const emitsUvNeverRun = q('Emits UV: never run it without its lens or UV glass, and replace cracked glass before use.',
  'Wikipedia: HMI light', 'https://en.wikipedia.org/wiki/HMI_light');
const colourTemperatureDriftsWith = q('Colour temperature drifts with lamp age, so meter each head rather than assuming 5600 K.',
  'Wikipedia: HMI light', 'https://en.wikipedia.org/wiki/HMI_light');
const theLampAloneDraws = q('The lamp alone draws 15 A at 120 V (8 A at 230 V), so use a 20 A circuit in 120 V countries. About the largest HMI that runs from a household outlet.',
  'Electrical: current = watts ÷ volts');
const tooMuchForA = q('Too much for a household socket: about 17 A at 230 V and over 33 A at 120 V before ballast losses. Plan a generator or a heavy-duty distro circuit.',
  'Electrical: current = watts ÷ volts');
const warmsAsItDims = q('Warms as it dims: at half output it is about 250 K warmer. FrameScan models this.',
  'How FrameScan models it');
const fullCtbToMatch = q('Full CTB to match daylight passes only about 36 % (1½ stops), so a tungsten unit makes a weak daylight source.',
  'LEE 201 Full CTB datasheet');
const runsVeryHotClip = q('Runs very hot. Clip gels to the barn doors\' gel frame, not the lens, and keep set dressing and drapes clear.',
  'General crew practice');
const silentNoFanAnd = q('Silent (no fan) and dims smoothly on a standard tungsten dimmer, which makes it easy to use for sound and for practical effects.',
  'General crew practice');
const drawsAbout8A = q('Draws about 8 A at 120 V or 4 A at 230 V; two will share a 20 A circuit at 120 V.',
  'Electrical: current = watts ÷ volts');
const drawsAbout17A = q('Draws about 17 A at 120 V, more than a standard 15 A household circuit; about 9 A at 230 V.',
  'Electrical: current = watts ÷ volts');
const lightsEverythingAroundIt = q('Lights everything around it, ceiling and walls included. Use a skirt to stop spill and keep contrast.',
  'General crew practice');
const framescanTreatsTheLantern = q('FrameScan treats the lantern as an even sphere; a skirt or half-skirt isn\'t modelled yet.',
  'How FrameScan models it');
const householdLedBulbsOften = q('Household LED bulbs often flicker on camera, especially on dimmers or at high frame rates. Test them, or swap for flicker-free film bulbs.',
  'Flicker-free dimming explainer', 'https://www.waveformlighting.com/film-photography/an-introduction-to-flicker-free-led-strip-dimming');
const manyArenTDimmable = q('Many aren\'t dimmable on an ordinary dimmer, and colour rendering is often only fair. Check the packaging before you rely on one.',
  'General crew practice');
const about2800K = q('About 2,800 K bare and warms further when dimmed, so it reads warmer than a 3200 K tungsten film light.',
  'How FrameScan models it');
const q100WHouseholdTungsten = q('100 W household tungsten bulbs are no longer sold in the EU and UK. Source them from film suppliers or use a dimmed photoflood.',
  'EU Regulation 244/2009', 'https://eur-lex.europa.eu/eli/reg/2009/244/oj');

export const fixtureQuirks: Record<string, UnitQuirk[]> = {
  'cob-100-bi': [dimmedLedsCanFlicker, theOutputFigureIs, allTheLightComes, biColourUnitsMix, mixedWhitesCanDrift],
  'cob-300-bi': [dimmedLedsCanFlicker, fanCooledQuietOr, theOutputFigureIs, allTheLightComes, biColourUnitsMix, mixedWhitesCanDrift],
  'cob-300-d': [dimmedLedsCanFlicker, fanCooledQuietOr, theOutputFigureIs, allTheLightComes],
  'cob-600-bi': [dimmedLedsCanFlicker, fanCooledQuietOr, theOutputFigureIs, allTheLightComes, biColourUnitsMix, mixedWhitesCanDrift],
  'cob-600-d': [dimmedLedsCanFlicker, fanCooledQuietOr, theOutputFigureIs, allTheLightComes],
  'cob-1200-d': [dimmedLedsCanFlicker, fanCooledQuietOr, theOutputFigureIs, allTheLightComes, atFullOutputIt],
  'fresnel-led-200-bi': [dimmedLedsCanFlicker, fanCooledQuietOr, biColourUnitsMix, mixedWhitesCanDrift, theOutputFigureIs2, aFresnelSSoft],
  'fresnel-led-600-d': [dimmedLedsCanFlicker, fanCooledQuietOr, theOutputFigureIs2, aFresnelSSoft],
  'panel-1x1-bi': [dimmedLedsCanFlicker, biColourUnitsMix, mixedWhitesCanDrift, barePanelsAreMade, barnDoorsOnA],
  'panel-1x1-rgb': [dimmedLedsCanFlicker, saturatedColoursGiveFar, unitsWithOnlyRed, barePanelsAreMade, barnDoorsOnA],
  'panel-2x1-bi': [dimmedLedsCanFlicker, biColourUnitsMix, mixedWhitesCanDrift, barePanelsAreMade, barnDoorsOnA],
  'panel-2x1-rgb': [dimmedLedsCanFlicker, saturatedColoursGiveFar, unitsWithOnlyRed, barePanelsAreMade, barnDoorsOnA],
  'tube-2ft-rgb': [dimmedLedsCanFlicker, saturatedColoursGiveFar, unitsWithOnlyRed, batteryRunTimeIs, framescanTreatsTheTube],
  'tube-4ft-rgb': [dimmedLedsCanFlicker, saturatedColoursGiveFar, unitsWithOnlyRed, batteryRunTimeIs, framescanTreatsTheTube],
  'mat-2x2-bi': [dimmedLedsCanFlicker, biColourUnitsMix, mixedWhitesCanDrift, aFlexibleMatNeeds, theDriverIsUsually],
  'mat-4x4-bi': [dimmedLedsCanFlicker, biColourUnitsMix, mixedWhitesCanDrift, aFlexibleMatNeeds, theDriverIsUsually],
  'hmi-1800-par': [takesAFewMinutes, mostHeadsCanT, dimsOnlyToAbout, useAnElectronicBallast, emitsUvNeverRun, colourTemperatureDriftsWith, theLampAloneDraws],
  'hmi-4000-par': [takesAFewMinutes, mostHeadsCanT, dimsOnlyToAbout, useAnElectronicBallast, emitsUvNeverRun, colourTemperatureDriftsWith, tooMuchForA],
  'tungsten-650': [warmsAsItDims, fullCtbToMatch, runsVeryHotClip, silentNoFanAnd],
  'tungsten-1k': [warmsAsItDims, fullCtbToMatch, runsVeryHotClip, silentNoFanAnd, drawsAbout8A],
  'tungsten-2k': [warmsAsItDims, fullCtbToMatch, runsVeryHotClip, silentNoFanAnd, drawsAbout17A],
  'lantern-300-bi': [dimmedLedsCanFlicker, fanCooledQuietOr, biColourUnitsMix, mixedWhitesCanDrift, lightsEverythingAroundIt, framescanTreatsTheLantern],
  'bulb-led-60': [householdLedBulbsOften, manyArenTDimmable],
  'bulb-tungsten-100': [about2800K, q100WHouseholdTungsten],
};

// Cameras
const upTo40Fps = q('Up to 40 fps in this mode (ARRIRAW or ProRes). Rates can change with software and licences.',
  'ARRI Mini LF recording formats', 'https://www.arri.com/resource/blob/306446/d7bf94ecd6bc57c4b430b360b7cdc7e6/alexa-mini-lf-recording-formats-sheet-din-a4-size-pdf-data.pdf');
const needsA4471 = q('Needs a 44.71 mm image circle: only true large-format lenses cover it without vignetting.',
  'ARRI Alexa Mini LF', 'https://www.arri.com/alexaminilf');
const builtInNdFilters = q('Built-in ND filters, LPL mount (PL with the adapter).',
  'ARRI Alexa Mini LF', 'https://www.arri.com/alexaminilf');
const upTo60Fps = q('Up to 60 fps in 3.8K UHD; the larger 4.3K 16:9 mode (35.64 × 20.05 mm) is ProRes only and stops at 48 fps. Rates can change with software and licences.',
  'ARRI Mini LF recording formats', 'https://www.arri.com/resource/blob/306446/d7bf94ecd6bc57c4b430b360b7cdc7e6/alexa-mini-lf-recording-formats-sheet-din-a4-size-pdf-data.pdf');
const manySuper35Lenses = q('Many Super 35 lenses cover LF 16:9. Check yours with ARRI\'s lens illumination tool.',
  'ARRI Mini LF FAQ', 'https://arri.com/en/learn-help/learn-help-camera-system/frequently-asked-questions/alexa-mini-lf-faq');
const upTo75Fps = q('Up to 75 fps ARRIRAW on a 2 TB drive (35 fps on 1 TB), 60 fps ProRes. Rates can change with software and licences.',
  'ARRI Alexa 35 format poster', 'https://www.arri.com/resource/blob/296424/88454a5a3dee9fe1d3fd68e75aa3411e/alexa-35-recording-format-poster-data.pdf');
const needsA3396 = q('Needs a 33.96 mm image circle, larger than classic Super 35: check lens coverage.',
  'ARRI Alexa 35 format poster', 'https://www.arri.com/resource/blob/296424/88454a5a3dee9fe1d3fd68e75aa3411e/alexa-35-recording-format-poster-data.pdf');
const openGateNeedsArri = q('Open Gate needs ARRI\'s Open Gate / anamorphic licence on cameras that don\'t include it.',
  'ARRI Alexa 35', 'https://arri.com/en/camera-systems/cameras/alexa-35');
const upTo120Fps = q('Up to 120 fps ARRIRAW on a 2 TB drive (55 on 1 TB), 100 fps ProRes, with the high-speed licence. Rates can change with software and licences.',
  'ARRI Alexa 35 format poster', 'https://www.arri.com/resource/blob/296424/88454a5a3dee9fe1d3fd68e75aa3411e/alexa-35-recording-format-poster-data.pdf');
const q2855MmImage = q('28.55 mm image circle: classic Super 35 lenses cover it.',
  'ARRI Alexa 35 format poster', 'https://www.arri.com/resource/blob/296424/88454a5a3dee9fe1d3fd68e75aa3411e/alexa-35-recording-format-poster-data.pdf');
const openGateRecordsArriraw = q('Open Gate records ARRIRAW only.',
  'ARRI Alexa Mini recording areas', 'https://www.arri.com/resource/blob/178064/d84031615b6bf09446aeb7972066b129/alexa-mini-recording-areas-surround-views-and-framelines-sup-4-0-data.pdf');
const needsA3359 = q('Needs a 33.59 mm image circle, more than standard Super 35 lenses are designed for.',
  'ARRI Alexa Mini recording areas', 'https://www.arri.com/resource/blob/178064/d84031615b6bf09446aeb7972066b129/alexa-mini-recording-areas-surround-views-and-framelines-sup-4-0-data.pdf');
const forHighSpeedThe = q('For high speed the Mini drops to smaller modes (up to 200 fps in 2.8K 16:9).',
  'ARRI Mini LF FAQ', 'https://arri.com/en/learn-help/learn-help-camera-system/frequently-asked-questions/alexa-mini-lf-faq');
const upTo30Fps = q('Up to 30 fps in 8.6K 3:2; 8.6K 17:9 reaches 48 fps and 8.2K 17:9 60 fps. Rates can change with software and licences.',
  'Sony Venice 2 recording formats', 'https://77snszqv.media.zestyio.com/Sony_VENICE2_RecordingFormats.pdf');
const needsA432 = q('Needs a 43.2 mm image circle: use large-format lenses.',
  'Sony Venice 2 recording formats', 'https://77snszqv.media.zestyio.com/Sony_VENICE2_RecordingFormats.pdf');
const builtIn8Step = q('Built-in 8-step ND (0.3 to 2.4). PL mount, or E-mount with the lens lock removed.',
  'Sony Venice 2', 'https://pro.sony/en_AU/products/digital-cinema-cameras/venice2');
const upTo30Fps2 = q('Up to 30 fps as standard; 72 fps needs the high frame rate licence. Rates can change with software and licences.',
  'Sony Venice', 'https://pro.sony/ue_US/pro/product/venice');
const fullFrameModesNeed = q('Full-frame modes need the full frame licence on the original Venice.',
  'Sony Venice', 'https://pro.sony/ue_US/pro/product/venice');
const upTo60Fps2 = q('Up to 60 fps as standard, 110 fps with the high frame rate licence. Rates can change with software and licences.',
  'Sony Venice', 'https://pro.sony/ue_US/pro/product/venice');
const thisModeIsOn = q('This mode is on the original Venice (and the Venice 2 6K sensor). The Venice 2 8K sensor\'s Super 35 modes start at 5.4K.',
  'Sony Venice 2 format chart', 'https://www.sony.jp/ls-camera/reference/pdf/VENICE_2_MPC-3628_recording_format.pdf');
const theFx6HasA = q('The FX6 has a built-in electronic variable ND; the FX3 has no internal ND, so plan screw-in or matte-box ND.',
  'Sony FX6', 'https://pro.sony/ue_US/products/handheld-camcorders/ilme-fx6v');
const bothRecord4kUp = q('Both record 4K up to 120 fps internally.',
  'Sony FX3 specifications', 'https://www.sony-mea.com/en/electronics/interchangeable-lens-cameras/ilme-fx3a/specifications');
const eMountSonyPublishes = q('E-mount. Sony publishes the sensor as 35.6 × 23.8 mm; this preset is its full-width 16:9 area.',
  'Sony FX3 specifications', 'https://www.sony-mea.com/en/electronics/interchangeable-lens-cameras/ilme-fx3a/specifications');
const upTo120Fps2 = q('Up to 120 fps at 8K 17:9 (150 fps at 2.4:1). Rates can change with software and licences.',
  'RED V-Raptor', 'https://www.red.com/v-raptor_4');
const theOriginalVRaptor = q('The original V-Raptor has a rolling shutter; the V-Raptor [X] models are global shutter.',
  'RED V-Raptor', 'https://www.red.com/v-raptor_4');
const q4631MmImage = q('46.31 mm image circle: use VV / large-format lenses. RF mount, PL with an adapter.',
  'RED V-Raptor', 'https://www.red.com/v-raptor_4');
const a6kWindowOf = q('A 6K window of the 8K VV sensor: up to 160 fps at 17:9 (200 fps at 2.4:1). Rates can change with software and licences.',
  'RED V-Raptor', 'https://www.red.com/v-raptor_4');
const widerThanClassicSuper = q('Wider than classic Super 35 (30.7 mm): some S35 lenses vignette in the corners.',
  'General crew practice');
const rfMountPlWith = q('RF mount, PL with an adapter.',
  'RED V-Raptor', 'https://www.red.com/v-raptor_4');
const globalShutterNoRolling = q('Global shutter: no rolling-shutter skew on whip pans or flashing lights.',
  'RED Komodo 6K tech specs', 'https://docs.red.com/955-0196_v1.6/Content/A_TechSpecs/Specs_KOMODO_6K.htm');
const q6k179Stops = q('6K 17:9 stops at 40 fps; drop to 4K for 60 fps or 2K for 120 fps. Rates can change with software and licences.',
  'RED Komodo 6K tech specs', 'https://docs.red.com/955-0196_v1.6/Content/A_TechSpecs/Specs_KOMODO_6K.htm');
const noBuiltInNd = q('No built-in ND. RF mount; ND needs filters or an electronic-ND lens adapter.',
  'RED Komodo 6K tech specs', 'https://docs.red.com/955-0196_v1.6/Content/A_TechSpecs/Specs_KOMODO_6K.htm');
const super35LensesOnly = q('Super 35 lenses only cover the centre of a full-frame sensor; expect vignetting unless you crop.',
  'Wikipedia: full-frame sensor', 'https://en.wikipedia.org/wiki/Full-frame_digital_SLR');
const theFullSilentAperture = q('The full silent aperture: about 32 % more area than 35 mm Academy.',
  'Wikipedia: Super 35', 'https://en.wikipedia.org/wiki/Super_35');
const mostAnamorphic2Lenses = q('Most anamorphic 2× lenses are designed for this 4-perf frame height.',
  'General crew practice');
const a169Crop = q('A 16:9 crop of the Super 35 width; the height is derived from the 24.89 mm width.',
  'Wikipedia: Super 35', 'https://en.wikipedia.org/wiki/Super_35');
const cropFactor20 = q('Crop factor 2.0 against full frame: a 25 mm lens frames like a 50 mm on full frame.',
  'Wikipedia: Micro Four Thirds', 'https://en.wikipedia.org/wiki/Micro_Four_Thirds_system');
const videoModesRecordA = q('Video modes record a 16:9 or 17:9 crop of this 4:3 area, so the real frame is a little shorter.',
  'Wikipedia: Micro Four Thirds', 'https://en.wikipedia.org/wiki/Micro_Four_Thirds_system');
const needsSuper16Lenses = q('Needs Super 16 lenses: standard 16 mm lenses can vignette on the wider frame.',
  'Wikipedia: Super 16', 'https://en.wikipedia.org/wiki/Super_16_mm_film');
const nativeAspectAbout1 = q('Native aspect about 1.69:1 (12.52 × 7.41 mm), close to 16:9.',
  'Wikipedia: Super 16', 'https://en.wikipedia.org/wiki/Super_16_mm_film');

export const sensorQuirks: Record<string, UnitQuirk[]> = {
  'arri-35-og': [upTo75Fps, needsA3396, openGateNeedsArri],
  'arri-35-169': [upTo120Fps, q2855MmImage],
  'arri-minilf-og': [upTo40Fps, needsA4471, builtInNdFilters],
  'arri-minilf-169': [upTo60Fps, manySuper35Lenses, builtInNdFilters],
  'arri-mini-og': [openGateRecordsArriraw, needsA3359, forHighSpeedThe],
  'red-vraptor-8k-vv': [upTo120Fps2, theOriginalVRaptor, q4631MmImage],
  'red-vraptor-6k-s35': [a6kWindowOf, widerThanClassicSuper, rfMountPlWith],
  'red-komodo-6k': [globalShutterNoRolling, q6k179Stops, noBuiltInNd],
  'sony-venice2-86k': [upTo30Fps, needsA432, builtIn8Step],
  'sony-venice-6k-179': [upTo30Fps2, fullFrameModesNeed, builtIn8Step],
  'sony-venice-4k-s35': [upTo60Fps2, thisModeIsOn],
  'sony-fx6': [theFx6HasA, bothRecord4kUp, eMountSonyPublishes],
  'generic-ff': [super35LensesOnly],
  'generic-s35-4perf': [theFullSilentAperture, mostAnamorphic2Lenses],
  'generic-s35-169': [a169Crop],
  'generic-m43': [cropFactor20, videoModesRecordA],
  'generic-s16': [needsSuper16Lenses, nativeAspectAbout1],
};

export const quirksForFixture = (id: string): UnitQuirk[] => fixtureQuirks[id] ?? [];
export const quirksForSensor = (id: string): UnitQuirk[] => sensorQuirks[id] ?? [];
