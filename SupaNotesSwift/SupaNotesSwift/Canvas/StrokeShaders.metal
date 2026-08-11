#include <metal_stdlib>
using namespace metal;

constant float4x4 catmullRomBasis = float4x4(
  float4(0, 1, 0, 0),
  float4(-0.5, 0, 0.5, 0),
  float4(1, -2.5, 2, -0.5),
  float4(-0.5, 1.5, -1.5, 0.5)
);

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
  float4 tVec = float4(1, t, t * t, t * t * t);

  float4 weights = catmullRomBasis * tVec;

  float4 px = float4(p0.x, p1.x, p2.x, p3.x);
  float4 py = float4(p0.y, p1.y, p2.y, p3.y);

  float2 result = float2(dot(weights, px), dot(weights, py));
  outputPoints[gid] = packed_float2(result);
}
