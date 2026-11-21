// Depth of field for the look-through view. Each pixel is blurred by the size of the blur circle the
// real lens would make at that distance (focus.ts blurDiameter), scaled from millimetres on the sensor to
// pixels of the frame. A gather blur, not a ray-traced bokeh: it reads the frame's softness right but
// is rough at edges where a soft foreground crosses a sharp subject.
import * as THREE from 'three';
import { Pass, FullScreenQuad } from 'three/examples/jsm/postprocessing/Pass.js';

const TAPS = 64;
const MAX_RADIUS = 24; // px; very soft backgrounds stop growing here (the look, not the maths, is the limit)

const shader = {
  uniforms: {
    tColor: { value: null as THREE.Texture | null },
    tDepth: { value: null as THREE.Texture | null },
    texel: { value: new THREE.Vector2(1, 1) },
    near: { value: 0.05 }, far: { value: 200 },
    focus: { value: 3 },
    /** f² / (N (s − f)) in sensor mm: the blur circle of a point at infinity. */
    blurAtInfinity: { value: 0 },
    pxPerMm: { value: 0 },
  },
  vertexShader: /* glsl */`
    varying vec2 vUv;
    void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: /* glsl */`
    #include <packing>
    #define TAPS ${TAPS}
    #define MAX_RADIUS ${MAX_RADIUS.toFixed(1)}
    uniform sampler2D tColor; uniform sampler2D tDepth;
    uniform vec2 texel; uniform float near; uniform float far;
    uniform float focus; uniform float blurAtInfinity; uniform float pxPerMm;
    varying vec2 vUv;
    float distanceAt(vec2 uv) {
      float d = unpackRGBAToDepth(texture2D(tDepth, uv));
      return -perspectiveDepthToViewZ(d, near, far);
    }
    // Blur-circle radius in pixels for something at distance z.
    float radiusAt(float z) {
      return min(MAX_RADIUS, 0.5 * blurAtInfinity * abs(z - focus) / max(z, 1e-3) * pxPerMm);
    }
    void main() {
      vec4 base = texture2D(tColor, vUv);
      float z = distanceAt(vUv);
      float r = radiusAt(z);
      if (r < 0.5) { gl_FragColor = base; return; }
      vec3 sum = base.rgb; float weight = 1.0;
      const float golden = 2.39996323;
      for (int i = 1; i < TAPS; i++) {
        float fi = float(i);
        float dist = r * sqrt(fi / float(TAPS));
        float a = fi * golden;
        vec2 uv = vUv + vec2(cos(a), sin(a)) * dist * texel;
        float sz = distanceAt(uv);
        // A sharp thing in front must not smear onto a soft background; a soft thing behind is limited
        // to this pixel's own blur so a soft background doesn't eat a sharp subject's edge.
        float reach = sz < z ? radiusAt(sz) : min(radiusAt(sz), r);
        float w = smoothstep(dist - 1.0, dist + 1.0, reach);
        sum += texture2D(tColor, uv).rgb * w; weight += w;
      }
      gl_FragColor = vec4(sum / weight, base.a);
    }`,
};

export class DepthOfFieldPass extends Pass {
  private depthTarget = new THREE.WebGLRenderTarget(1, 1, { minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter });
  private depthMaterial = new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, blending: THREE.NoBlending });
  private material = new THREE.ShaderMaterial({ ...shader, uniforms: THREE.UniformsUtils.clone(shader.uniforms) });
  private quad = new FullScreenQuad(this.material);
  private clearColor = new THREE.Color();

  /** `hide` names objects the depth must ignore (haze, glass, cut-away walls). */
  constructor(private scene: THREE.Scene, private camera: THREE.PerspectiveCamera, private hide: (o: THREE.Object3D) => boolean) {
    super();
    this.enabled = false;
  }

  /** Focus distance (m), the lens (focal mm, f-number) and how many drawing-buffer pixels one sensor mm covers. */
  set(focusM: number, focalMm: number, fNumber: number, pxPerMm: number) {
    const f = focalMm / 1000, s = Math.max(focusM, f * 1.01);
    const u = this.material.uniforms;
    u.focus.value = s;
    u.blurAtInfinity.value = (f * f) / (Math.max(fNumber, 0.5) * (s - f)) * 1000;
    u.pxPerMm.value = pxPerMm;
  }

  setSize(w: number, h: number) {
    this.depthTarget.setSize(w, h);
    this.material.uniforms.texel.value.set(1 / w, 1 / h);
  }

  render(renderer: THREE.WebGLRenderer, writeBuffer: THREE.WebGLRenderTarget, readBuffer: THREE.WebGLRenderTarget) {
    const { scene, camera } = this;
    const hidden: THREE.Object3D[] = [];
    scene.traverse(o => { if (o.visible && this.hide(o)) { o.visible = false; hidden.push(o); } });
    const background = scene.background, override = scene.overrideMaterial, fog = scene.fog;
    renderer.getClearColor(this.clearColor);
    const alpha = renderer.getClearAlpha(), autoClear = renderer.autoClear;
    scene.background = null; scene.overrideMaterial = this.depthMaterial; scene.fog = null;
    renderer.setClearColor(0xffffff, 1); renderer.autoClear = false; // white = far away
    renderer.setRenderTarget(this.depthTarget);
    renderer.clear();
    renderer.render(scene, camera);
    scene.background = background; scene.overrideMaterial = override; scene.fog = fog;
    for (const o of hidden) o.visible = true;
    renderer.setClearColor(this.clearColor, alpha); renderer.autoClear = autoClear;

    const u = this.material.uniforms;
    u.tColor.value = readBuffer.texture; u.tDepth.value = this.depthTarget.texture;
    u.near.value = camera.near; u.far.value = camera.far;
    renderer.setRenderTarget(this.renderToScreen ? null : writeBuffer);
    if (this.clear) renderer.clear();
    this.quad.render(renderer);
  }

  dispose() { this.depthTarget.dispose(); this.depthMaterial.dispose(); this.material.dispose(); this.quad.dispose(); }
}
