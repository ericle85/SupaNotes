#include <metal_stdlib>
using namespace metal;

struct StampVertex {
  float4 position [[position]];
  float2 uv;
};

kernel void catmullRomCompute(
    device const packed_float2* controlPoints [[buffer(0)]],
    device packed_float2* outputPoints [[buffer(1)]],
    constant uint& pointCount [[buffer(2)]],
    constant uint& subdivisions [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
  uint totalOutputs = (pointCount - 1) * subdivisions;
  if (gid >= totalOutputs) {
    return;
  }

  uint segIdx = gid / subdivisions;
  uint subIdx = gid % subdivisions;

  int last = int(pointCount) - 1;
  int i = int(segIdx);

  float2 p0 = float2(controlPoints[max(i - 1, 0)]);
  float2 p1 = float2(controlPoints[i]);
  float2 p2 = float2(controlPoints[min(i + 1, last)]);
  float2 p3 = float2(controlPoints[min(i + 2, last)]);

  float t = float(subIdx + 1) / float(subdivisions);
  float t2 = t * t;
  float t3 = t2 * t;

  float2 result = 0.5f * (
      (2.0f * p1) +
      (-p0 + p2) * t +
      (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * t2 +
      (-p0 + 3.0f * p1 - 3.0f * p2 + p3) * t3
  );

  outputPoints[gid] = packed_float2(result);
}

vertex StampVertex stampVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device const packed_float2* points [[buffer(0)]],
    constant float2& viewportSize [[buffer(1)]],
    constant float& radius [[buffer(2)]]
) {
  float2 center = float2(points[instanceID]);

  float2 corners[4] = {
    float2(-1, -1), float2(1, -1),
    float2(-1, 1), float2(1, 1)
  };

  float2 uv = corners[vertexID];
  float2 pos = center + uv * radius;

  float2 ndc = (pos / viewportSize) * 2.0f - 1.0f;
  ndc.y = -ndc.y;

  StampVertex out;
  out.position = float4(ndc, 0, 1);
  out.uv = uv;
  return out;
}

fragment float4 stampFragment(
    StampVertex in [[stage_in]],
    constant float4& color [[buffer(0)]]
) {
  float dist = length(in.uv);
  if (dist > 1.0f) {
    discard_fragment();
  }
  float alpha = 1.0f - smoothstep(0.85f, 1.0f, dist);
  return float4(color.rgb, color.a * alpha);
}
