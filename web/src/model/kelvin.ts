// Port of `Kelvin.rgb` (Lighting.swift): approximate black-body colour, Tanner Helland's fit.
export function kelvinRGB(kelvin: number): { r: number; g: number; b: number } {
  const t = Math.min(Math.max(kelvin, 1000), 15000) / 100;
  let r: number, g: number, b: number;
  if (t <= 66) {
    r = 255;
    g = 99.4708025861 * Math.log(t) - 161.1195681661;
    b = t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
  } else {
    r = 329.698727446 * Math.pow(t - 60, -0.1332047592);
    g = 288.1221695283 * Math.pow(t - 60, -0.0755148492);
    b = 255;
  }
  const c = (v: number) => Math.min(Math.max(v, 0), 255) / 255;
  return { r: c(r), g: c(g), b: c(b) };
}

export const kelvinPresets = [2700, 3200, 4300, 5600, 6500];

export const cssRGB = (c: { r: number; g: number; b: number }, a = 1) =>
  `rgba(${Math.round(c.r * 255)}, ${Math.round(c.g * 255)}, ${Math.round(c.b * 255)}, ${a})`;
