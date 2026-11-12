// Port of SolarCalculator.position (FrameScout/Core/Services/SolarCalculator.swift): the NOAA solar
// position algorithm, accurate to well under a degree for 1900–2100. Same steps, same constants.
const rad = (d: number) => d * Math.PI / 180;
const deg = (r: number) => r * 180 / Math.PI;
const fmod = (a: number, b: number) => a % b; // like Swift's truncatingRemainder

export interface SolarPosition { /** Degrees clockwise from true north. */ azimuth: number; /** Degrees above the horizon. */ elevation: number }

export function solarPosition(date: Date, latitude: number, longitude: number, refraction = true): SolarPosition {
  const secs = date.getTime() / 1000;
  const jd = secs / 86400 + 2440587.5;
  const t = (jd - 2451545.0) / 36525.0;
  let l0 = fmod(280.46646 + t * (36000.76983 + t * 0.0003032), 360);
  if (l0 < 0) l0 += 360;
  const m = 357.52911 + t * (35999.05029 - 0.0001537 * t);
  const e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
  const c = Math.sin(rad(m)) * (1.914602 - t * (0.004817 + 0.000014 * t))
    + Math.sin(rad(2 * m)) * (0.019993 - 0.000101 * t)
    + Math.sin(rad(3 * m)) * 0.000289;
  const trueLong = l0 + c;
  const omega = 125.04 - 1934.136 * t;
  const lambda = trueLong - 0.00569 - 0.00478 * Math.sin(rad(omega));
  const eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60;
  const eps = eps0 + 0.00256 * Math.cos(rad(omega));
  const decl = Math.asin(Math.sin(rad(eps)) * Math.sin(rad(lambda)));
  const y = Math.pow(Math.tan(rad(eps / 2)), 2);
  const eqTime = 4 * deg(
    y * Math.sin(2 * rad(l0))
    - 2 * e * Math.sin(rad(m))
    + 4 * e * y * Math.sin(rad(m)) * Math.cos(2 * rad(l0))
    - 0.5 * y * y * Math.sin(4 * rad(l0))
    - 1.25 * e * e * Math.sin(2 * rad(m)),
  );
  const secondsIntoDay = fmod(secs, 86400);
  const utcMinutes = (secondsIntoDay < 0 ? secondsIntoDay + 86400 : secondsIntoDay) / 60;
  let trueSolarTime = fmod(utcMinutes + eqTime + 4 * longitude, 1440);
  if (trueSolarTime < 0) trueSolarTime += 1440;
  let hourAngle = trueSolarTime / 4 - 180;
  if (hourAngle < -180) hourAngle += 360;
  const latR = rad(latitude), haR = rad(hourAngle);
  const cosZenith = Math.max(-1, Math.min(1, Math.sin(latR) * Math.sin(decl) + Math.cos(latR) * Math.cos(decl) * Math.cos(haR)));
  let elevation = 90 - deg(Math.acos(cosZenith));
  let azimuth = fmod(deg(Math.atan2(Math.sin(haR), Math.cos(haR) * Math.sin(latR) - Math.tan(decl) * Math.cos(latR))) + 180, 360);
  if (azimuth < 0) azimuth += 360;
  if (refraction) elevation += refractionCorrection(elevation);
  return { azimuth, elevation };
}

function refractionCorrection(e: number): number {
  if (e > 85) return 0;
  const te = Math.tan(rad(e));
  let arcsec: number;
  if (e > 5) arcsec = 58.1 / te - 0.07 / Math.pow(te, 3) + 0.000086 / Math.pow(te, 5);
  else if (e > -0.575) arcsec = 1735 + e * (-518.2 + e * (103.4 + e * (-12.79 + e * 0.711)));
  else arcsec = -20.772 / te;
  return arcsec / 3600;
}
