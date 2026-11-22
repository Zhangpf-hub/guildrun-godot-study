using System;
using System.Collections.Generic;
using System.Globalization;
using UnityEngine;

public static class ImpactSmokeBirthProbe
{
    public static void Measure()
    {
        var anchor = new GameObject("Ayaka").transform;
        anchor.localScale = Vector3.one * 1.14f;
        var source = new GameObject("Smoke_01").AddComponent<ParticleSystem>();
        source.transform.SetParent(anchor, false);
        source.transform.localPosition = Vector3.up * 0.5f;
        source.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        source.useAutoRandomSeed = false;
        source.randomSeed = 3964;
        var main = source.main;
        main.loop = false;
        main.duration = 1.0f;
        main.simulationSpace = ParticleSystemSimulationSpace.Local;
        main.scalingMode = ParticleSystemScalingMode.Hierarchy;
        main.startSpeed = new ParticleSystem.MinMaxCurve(2.0f, 0.0f);
        main.startLifetime = new ParticleSystem.MinMaxCurve(2.0f, 1.600000023841858f);
        main.startSize = new ParticleSystem.MinMaxCurve(1.0f, 4.0f);
        main.startRotation = new ParticleSystem.MinMaxCurve(0.0f, 6.283185005187988f);
        main.startColor = new Color(0.3305973708629608f, 0.30588236451148987f, 0.3490196168422699f, 0.1568627506494522f);
        var shape = source.shape;
        shape.shapeType = ParticleSystemShapeType.Cone;
        shape.angle = 25;
        shape.radius = 0.5f;
        shape.radiusThickness = 1.0f;
        shape.rotation = new Vector3(-90.0f, 0, 0);
        var emission = source.emission;
        emission.rateOverTime = 0;
        emission.SetBursts(new [] { new ParticleSystem.Burst(0.0f, 5, 5, 2, 0.05f) });
        var velocity = source.velocityOverLifetime;
        velocity.enabled = true;
        velocity.speedModifier = new ParticleSystem.MinMaxCurve(1.0f, new AnimationCurve(
            new Keyframe(0.0f, 1.0f), new Keyframe(.43316650390625f, .045745849609375f),
            new Keyframe(.9900989532470703f, 0.0f)));
        var colorBySpeed = source.colorBySpeed;
        var gradient = new Gradient();
        gradient.SetKeys(new [] {new GradientColorKey(Color.white, 0), new GradientColorKey(Color.white, 1)},
            new [] {new GradientAlphaKey(1, 0), new GradientAlphaKey(0, 1)});
        colorBySpeed.enabled = true;
        colorBySpeed.color = gradient;
        colorBySpeed.range = new Vector2(4, 12);
        var atlas = source.textureSheetAnimation;
        atlas.enabled = true;
        atlas.numTilesX = 6;
        atlas.numTilesY = 6;
        atlas.frameOverTime = new ParticleSystem.MinMaxCurve(.9998999834060669f, AnimationCurve.Linear(0, 0, 1, 1));
        var custom = source.customData;
        custom.enabled = true;
        custom.SetMode(ParticleSystemCustomData.Custom1, ParticleSystemCustomDataMode.Vector);
        custom.SetMode(ParticleSystemCustomData.Custom2, ParticleSystemCustomDataMode.Vector);
        custom.SetVectorComponentCount(ParticleSystemCustomData.Custom1, 4);
        custom.SetVectorComponentCount(ParticleSystemCustomData.Custom2, 4);
        for (var i = 0; i < 4; i++)
        {
            custom.SetVector(ParticleSystemCustomData.Custom1, i, 0);
            custom.SetVector(ParticleSystemCustomData.Custom2, i, 0);
        }
        var ageCurve = new ParticleSystem.MinMaxCurve(1.0f, AnimationCurve.Linear(0, 0, 1, 1));
        custom.SetVector(ParticleSystemCustomData.Custom1, 2, ageCurve);
        custom.SetVector(ParticleSystemCustomData.Custom1, 3, ageCurve);
        custom.SetVector(ParticleSystemCustomData.Custom2, 0, ageCurve);
        custom.SetVector(ParticleSystemCustomData.Custom2, 1, ageCurve);
        var renderer = source.GetComponent<ParticleSystemRenderer>();
        renderer.applyActiveColorSpace = true;
        renderer.SetActiveVertexStreams(new List<ParticleSystemVertexStream> {
            ParticleSystemVertexStream.Position, ParticleSystemVertexStream.Normal,
            ParticleSystemVertexStream.Color, ParticleSystemVertexStream.UV,
            ParticleSystemVertexStream.Custom1XYZW, ParticleSystemVertexStream.Custom2XYZW,
        });
        var camera = new GameObject("Camera").AddComponent<Camera>();
        camera.orthographic = true;
        camera.transform.position = Vector3.back * 10;
        const float epsilon = .0001f;
        var buffer = new ParticleSystem.Particle[10];
        for (int repeat = 0; repeat < 2; repeat++)
        {
            for (int burst = 0; burst < 2; burst++)
            {
                source.Simulate(burst == 0 ? epsilon : .05f, true, burst == 0, false);
                int count = source.GetParticles(buffer);
                if (count != (burst + 1) * 5)
                    throw new Exception($"Expected {(burst + 1) * 5} particles, measured {count}.");
                for (int i = burst * 5; i < count; i++)
                {
                    var p = buffer[i];
                    var age = p.startLifetime - p.remainingLifetime;
                    var center = p.position - p.velocity * age;
                    var values = new [] { center.x, center.y, center.z, p.velocity.x, p.velocity.y, p.velocity.z,
                        p.startSize, p.startLifetime, p.rotation };
                    string row = string.Join(",", Array.ConvertAll(values, x => x.ToString("F7", CultureInfo.InvariantCulture)));
                    Debug.Log($"SMOKE_BIRTH {repeat} {burst} {p.randomSeed} [{row}]");
                }
            }
            var mesh = new Mesh();
            renderer.BakeMesh(mesh, camera, ParticleSystemBakeMeshOptions.BakeRotationAndScale | ParticleSystemBakeMeshOptions.BakePosition);
            var v = mesh.vertices;
            var localSize = buffer[0].GetCurrentSize(source);
            var meshCenter = (v[0] + v[1] + v[2] + v[3]) / 4;
            Debug.Log($"SMOKE_BAKE width={(v[1] - v[0]).magnitude:F6} localSize={localSize:F6} color={mesh.colors32[0]} local={buffer[0].position:F6} baked={meshCenter:F6}");
            UnityEngine.Object.DestroyImmediate(mesh);
        }
        var custom2 = new List<Vector4>(10);
        var uv1 = new List<Vector4>();
        var streamMesh = new Mesh();
        foreach (var age in new[] { 0.10f, 0.20f, 0.45f, 0.65f })
        {
            source.Simulate(age, true, true, false);
            source.GetParticles(buffer);
            source.GetCustomParticleData(custom2, ParticleSystemCustomData.Custom2);
            renderer.BakeMesh(streamMesh, camera, ParticleSystemBakeMeshOptions.Default);
            streamMesh.GetUVs(1, uv1);
            float lifetimeProgress = 1.0f - buffer[0].remainingLifetime / buffer[0].startLifetime;
            Debug.Log($"SMOKE_STREAM age={age:F3} progress={lifetimeProgress:F6} custom2={custom2[0]:F6} texcoord1={uv1[0]:F6}");
            if (custom2[0].x <= 0.0f || Mathf.Abs(uv1[0].z - custom2[0].x) > 0.0001f)
                throw new Exception($"Missing positive Custom2.x in TEXCOORD1.z at age {age}.");
        }
        UnityEngine.Object.DestroyImmediate(streamMesh);
        UnityEngine.Object.DestroyImmediate(anchor.gameObject);
        UnityEngine.Object.DestroyImmediate(camera.gameObject);
    }
}
