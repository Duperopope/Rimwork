using System;

namespace RimWorldLab
{
    public class LabManager
    {
        private float defaultTemperature = 20f;

        public void InitializeLab(int id)
        {
            // Placeholder initialization logic
            Console.WriteLine($"Initializing lab with ID: {id}");
        }

        public float GetDefaultTemperature()
        {
            return defaultTemperature;
        }
    }
}
