using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public static class CoreWhiteStreamProbe
{
    public static void Measure()
    {
        var shader = Shader.Find("Hidden/CoreStreamPixel");
        if (shader == null || SystemInfo.graphicsDeviceType != GraphicsDeviceType.Direct3D11)
            throw new InvalidOperationException("Import CoreStreamPixel.shader and run Unity with -force-d3d11.");

        var system = new GameObject("CoreWhite_01").AddComponent<ParticleSystem>();
        system.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        system.useAutoRandomSeed = false;
        system.randomSeed = 3964;
        var main = system.main;
        main.startSize = 1f;
        main.startSpeed = 0f;
        var shape = system.shape;
        shape.enabled = false;
        var data = system.customData;
        data.enabled = true;
        data.SetMode(ParticleSystemCustomData.Custom1, ParticleSystemCustomDataMode.Vector);
        data.SetVectorComponentCount(ParticleSystemCustomData.Custom1, 1);
        data.SetVector(ParticleSystemCustomData.Custom1, 0, 0.3f);

        var renderer = system.GetComponent<ParticleSystemRenderer>();
        renderer.SetActiveVertexStreams(new List<ParticleSystemVertexStream> {
            ParticleSystemVertexStream.Position,
            ParticleSystemVertexStream.Normal,
            ParticleSystemVertexStream.Color,
            ParticleSystemVertexStream.UV,
            ParticleSystemVertexStream.Custom1X,
        });
        var material = new Material(shader);
        renderer.sharedMaterial = material;
        system.Emit(1);
        system.Simulate(0.001f, false, false, false);

        var camera = new GameObject("Camera").AddComponent<Camera>();
        camera.transform.position = Vector3.back * 20f;
        camera.orthographic = true;
        camera.orthographicSize = 2f;
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = new Color(0, 0, 0, 0);
        var target = new RenderTexture(64, 64, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        var readback = new Texture2D(64, 64, TextureFormat.RGBAFloat, false, true);
        camera.targetTexture = target;
        var previousTarget = RenderTexture.active;
        var mesh = new Mesh();
        var baked = new GameObject("Baked");
        try
        {
            var values = new List<Vector4>();
            var uv = new List<Vector4>();
            system.GetCustomParticleData(values, ParticleSystemCustomData.Custom1);
            renderer.BakeMesh(mesh, camera, ParticleSystemBakeMeshOptions.Default);
            mesh.GetUVs(0, uv);
            var hasUv1 = mesh.HasVertexAttribute(VertexAttribute.TexCoord1);
            Debug.Log($"CORE_STREAM custom1={values[0]:F6} texcoord0={uv[0]:F6} has_texcoord1={hasUv1}");
            var particlePixel = ReadCenter(camera, readback);

            baked.AddComponent<MeshFilter>().sharedMesh = mesh;
            baked.AddComponent<MeshRenderer>().sharedMaterial = material;
            renderer.enabled = false;
            var bakedPixel = ReadCenter(camera, readback);
            mesh.SetUVs(1, new List<Vector4>(new Vector4[mesh.vertexCount]));
            var explicitPixel = ReadCenter(camera, readback);
            Debug.Log($"CORE_GPU particle={particlePixel:F6} baked={bakedPixel:F6} explicit_zero_uv1={explicitPixel:F6}");
            if (hasUv1 || !Mathf.Approximately(uv[0].z, 0.3f)
                || !Mathf.Approximately(particlePixel.g, 0.3f) || !Mathf.Approximately(bakedPixel.g, 0.3f)
                || !Mathf.Approximately(explicitPixel.a, 1f) || !Mathf.Approximately(explicitPixel.g, 0f))
                throw new InvalidOperationException("Unexpected TEXCOORD mapping on this renderer.");
        }
        finally
        {
            RenderTexture.active = previousTarget;
            UnityEngine.Object.DestroyImmediate(baked);
            UnityEngine.Object.DestroyImmediate(mesh);
            UnityEngine.Object.DestroyImmediate(camera.gameObject);
            UnityEngine.Object.DestroyImmediate(readback);
            UnityEngine.Object.DestroyImmediate(target);
            UnityEngine.Object.DestroyImmediate(system.gameObject);
            UnityEngine.Object.DestroyImmediate(material);
        }
    }

    static Color ReadCenter(Camera camera, Texture2D readback)
    {
        camera.Render();
        RenderTexture.active = camera.targetTexture;
        readback.ReadPixels(new Rect(0, 0, 64, 64), 0, 0);
        return readback.GetPixel(32, 32);
    }
}
