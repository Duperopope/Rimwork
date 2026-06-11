using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

// =====================================================================
// Dialogue: generates short lines of pawn-to-pawn chatter via a local
// LM Studio server, based on each pawn's current need state.
// =====================================================================

public class DialogueService
{
    private readonly HttpClient _http;
    private readonly string _url;
    private readonly string _model;

    public DialogueService(string url = "http://127.0.0.1:1234/v1/chat/completions", string model = "google/gemma-4-e2b")
    {
        _http = new HttpClient();
        _url = url;
        _model = model;
    }

    private static string DescribeNeed(NeedKind? need) => need switch
    {
        NeedKind.Hunger => "hungry",
        NeedKind.Fatigue => "tired",
        _ => "fine"
    };

    /// <summary>
    /// Asks the local LLM for a one-line exchange between two pawns who just met.
    /// Returns null on any error (timeout, server down, etc.) so callers can
    /// fail silently and just skip the bubble.
    /// </summary>
    public async Task<string?> GenerateLineAsync(string speakerName, NeedKind? speakerNeed, string otherName)
    {
        string prompt =
            $"{speakerName} (feeling {DescribeNeed(speakerNeed)}) just ran into {otherName} in a colony. " +
            "Write ONE short casual line of dialogue (under 12 words) that {speakerName} says. " +
            "Output ONLY the line, no quotes, no name prefix.";

        var body = new
        {
            model = _model,
            messages = new object[]
            {
                new { role = "user", content = prompt }
            },
            max_tokens = 150,
            temperature = 0.9
        };

        try
        {
            var json = JsonSerializer.Serialize(body);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            using var cts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(25));
            var response = await _http.PostAsync(_url, content, cts.Token);
            if (!response.IsSuccessStatusCode)
                return null;

            var responseText = await response.Content.ReadAsStringAsync(cts.Token);
            using var doc = JsonDocument.Parse(responseText);
            var line = doc.RootElement
                .GetProperty("choices")[0]
                .GetProperty("message")
                .GetProperty("content")
                .GetString();

            return line?.Trim().Trim('"');
        }
        catch
        {
            return null;
        }
    }
}
