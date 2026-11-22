using UnityEngine;

public static class FlightDustScaleProbe
{
    public static void Measure()
    {
        var anchor = new GameObject("Shuriken").transform;
        anchor.localScale = Vector3.one * .0114f;
        anchor.position = new Vector3(1, 3, 5);
        var dust = new GameObject("Dust_01").AddComponent<ParticleSystem>();
        dust.transform.SetParent(anchor, false);
        dust.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        dust.useAutoRandomSeed = false;
        dust.randomSeed = 7278;
        var main = dust.main;
        main.simulationSpace = ParticleSystemSimulationSpace.Local;
        main.scalingMode = ParticleSystemScalingMode.Local;
        main.startLifetime = new ParticleSystem.MinMaxCurve(.4f, .2f);
        main.startSize = new ParticleSystem.MinMaxCurve(.3f, .5f);
        main.startSpeed = new ParticleSystem.MinMaxCurve(.5f, -.5f);
        main.startRotation = new ParticleSystem.MinMaxCurve(-2 * Mathf.PI, 2 * Mathf.PI);
        main.startColor = new ParticleSystem.MinMaxGradient(Color.black, new Color(0, 0, 0, 0));
        var shape = dust.shape;
        shape.shapeType = ParticleSystemShapeType.Sphere;
        shape.radius = .6f;
        var emission = dust.emission;
        emission.rateOverTime = 0;
        emission.rateOverDistance = 2;
        var renderer = dust.GetComponent<ParticleSystemRenderer>();
        renderer.renderMode = ParticleSystemRenderMode.Billboard;
        renderer.alignment = ParticleSystemRenderSpace.View;
        var camera = new GameObject("Camera").AddComponent<Camera>();
        camera.transform.position = Vector3.back * 10;
        var mesh = new Mesh();
        var buffer = new ParticleSystem.Particle[20];
        dust.Play();
        dust.Simulate(.001f, true, false, false);
        foreach (float delta in new[] { 0.26f, 0.21f, 0.08f, 0.5f, 0.0f })
        {
            anchor.position += Vector3.right * delta;
            dust.Simulate(.016f, true, false, false);
            int count = dust.GetParticles(buffer);
            renderer.BakeMesh(mesh, camera, ParticleSystemBakeMeshOptions.BakeRotationAndScale | ParticleSystemBakeMeshOptions.BakePosition);
            if (count == 0)
            {
                Debug.Log($"FLIGHT_DUST delta={delta:F2} count={count}");
                continue;
            }
            var p = buffer[0];
            var v = mesh.vertices;
            var center = (v[0] + v[1] + v[2] + v[3]) / 4;
            var width = (v[0] - v[1]).magnitude;
            Debug.Log($"FLIGHT_DUST delta={delta:F2} count={count} alpha={p.startColor.a} local={p.position:F5} worldOffset={(center-anchor.position):F5} size={p.startSize:F5} width={width:F5}");
        }
        Object.DestroyImmediate(mesh);
        Object.DestroyImmediate(camera.gameObject);
        Object.DestroyImmediate(anchor.gameObject);
    }
}
