# Generates synthetic test recordings for the live Gemini tests
# (test/live/gemini_live_test.dart) using Windows' built-in voices.
# Output: build/voice_fixtures/*.wav (16 kHz mono, git-ignored).
#
#   powershell -ExecutionPolicy Bypass -File tool/make_voice_fixtures.ps1

Add-Type -AssemblyName System.Speech

$outDir = Join-Path $PSScriptRoot '..\build\voice_fixtures'
New-Item -ItemType Directory -Force $outDir | Out-Null

$doctor = 'Microsoft David Desktop'
$patient = 'Microsoft Zira Desktop'

function Write-Conversation($file, $lines) {
  $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
  $format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
    16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
    [System.Speech.AudioFormat.AudioChannel]::Mono)
  $synth.SetOutputToWaveFile((Join-Path $outDir $file), $format)
  $synth.Rate = 1
  foreach ($line in $lines) {
    $synth.SelectVoice($line[0])
    $synth.Speak($line[1])
    $synth.Speak(' ')
  }
  $synth.Dispose()
  Write-Output "wrote $file"
}

# Initial physiotherapy assessment of a knee, with findings said aloud.
Write-Conversation 'physio_session.wav' @(
  @($doctor, 'Good morning. Please sit down. What brings you in today?'),
  @($patient, 'Doctor, I have pain in my right knee for about three weeks. I twisted it while playing badminton.'),
  @($doctor, 'On a scale of zero to ten, how bad is the pain right now?'),
  @($patient, 'Right now it is about six. At its worst, when I climb stairs, it goes to eight.'),
  @($doctor, 'Where exactly do you feel it?'),
  @($patient, 'On the inner side of the right knee. Sometimes it feels like it catches or clicks.'),
  @($doctor, 'What makes it better?'),
  @($patient, 'Rest and ice help. Squatting and climbing stairs make it worse. I cannot sit cross legged on the floor.'),
  @($doctor, 'Any pain at night that wakes you up? Any fever, or weight loss?'),
  @($patient, 'No, no night pain, no fever and no weight loss.'),
  @($doctor, 'Are you taking any medicines for this?'),
  @($patient, 'I take a Combiflam tablet sometimes, when the pain is bad.'),
  @($doctor, 'Okay, let me examine. Right knee flexion is ninety five degrees, painful at the end of range. Left knee flexion is one hundred thirty five degrees. Extension is full.'),
  @($doctor, 'Mild swelling over the right knee. Tender on the medial joint line.'),
  @($doctor, 'McMurray test on the right is positive. Lachman test is negative. Quadriceps strength on the right is four by five.'),
  @($doctor, 'This looks like a medial meniscus injury of the right knee.'),
  @($doctor, 'Today I am giving you I F T on the right knee for fifteen minutes, and then ice for ten minutes.'),
  @($doctor, 'At home, do static quadriceps exercises, three sets of ten, hold for five seconds, twice a day. Also straight leg raises, three sets of ten, twice a day.'),
  @($doctor, 'Avoid squatting and sitting cross legged for now. Our goal is to get your pain below three out of ten in two weeks.'),
  @($doctor, 'Come for sessions three times a week. See you again after two days.')
)

# Front-desk dictation for the Add Patient form.
Write-Conversation 'patient_intake.wav' @(
  @($doctor, 'New patient. Name is Priya Deshmukh. She is thirty four years old.'),
  @($doctor, 'Mobile number nine eight two two three, four five six seven eight.'),
  @($doctor, 'Email priya dot deshmukh at the rate gmail dot com.'),
  @($doctor, 'She has right shoulder pain, frozen shoulder. She is diabetic, on metformin.'),
  @($doctor, 'She paid an advance of three thousand rupees for the package.')
)
