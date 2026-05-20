"""
Japanese→English mappings for JASCO footer metadata.

JASCO FTIR, Raman, and V-series UV-Vis exports embed footer keys (and a small
set of values) in Japanese. The parser stores the original Japanese key
untouched and adds an English-aliased entry resolving to the same value, so
callers can use either string.

English strings are JASCO's own UI terms, taken from the English-locale CSV
exports they ship. Stick to those when adding entries — even when a different
word would be more natural — so users can look up keys against the JASCO
software docs.

Adding a missing entry is a one-line PR — append to the appropriate dict.
"""

JAPANESE_KEY_TRANSLATIONS = Dict{String,String}(
    # Header / sample-identity block
    "試料名"                   => "Sample name",
    "コメント"                 => "Comment",
    "測定者"                   => "User",
    "所属"                     => "Division",
    "会社"                     => "Company",
    "オペレーター"             => "Operator",
    "作成日時"                 => "Creation date",
    "データタイプ"             => "Data array type",
    "横軸"                     => "Horizontal axis",
    "縦軸"                     => "Vertical axis",
    "スタート"                 => "Start",
    "エンド"                   => "End",
    "データ間隔"               => "Data interval",
    "データ数"                 => "Data points",
    "機種名"                   => "Model Name",
    "シリアル番号"             => "Serial Number",
    "測定日時"                 => "Measurement Date",
    # FTIR
    "光源"                     => "Light source",
    "光源切換"                 => "Light source change wavelength",
    "検出器"                   => "Detector",
    "積算回数"                 => "Accumulation",
    "分解"                     => "Resolution",
    "ゼロフィリング"           => "Zero-filling",
    "アポダイゼーション"       => "Apodization",
    "ゲイン"                   => "Gain",
    "アパーチャー"             => "Aperture",
    "スキャンスピード"         => "Scan speed",
    "フィルタ"                 => "Filter",
    # UV-Vis (V-series)
    "測光モード"               => "Photometric mode",
    "UV/Vis バンド幅"          => "UV/Vis bandwidth",
    "レスポンス"               => "Response",
    "走査速度"                 => "Scan speed",
    "付属品名"                 => "Accessory name",
    # Raman (NRS series)
    "露光時間"                 => "Exposure",
    "中心波数"                 => "Center wavenumber",
    "Zステージ位置"            => "Z position",
    "ビニング上限"             => "Binning Upper",
    "ビニング下限"             => "Binning Lower",
    "有効チャンネル範囲"       => "Valid Channel",
    "励起波長"                 => "Laser wavelength",
    "分光器"                   => "Monochromator",
    "グレーティング"           => "Grating",
    "スリット幅"               => "Slit",
    "リジェクションフィルター" => "Rejection filter",
    "対物レンズ"               => "Objective lens",
    "レーザー強度"             => "Laser power",
    "減光器"                   => "Attenuator",
    "宇宙線除去"               => "Cosmic ray reduction",
    "CCD温度"                  => "CCD temperature",
)

JAPANESE_VALUE_TRANSLATIONS = Dict{String,String}(
    "等間隔データ"     => "Linear data array",
    "不等間隔データ"   => "Non-linear data array",
    "標準光源"         => "Standard light source",
    "自動"             => "Automatic",
    "シングル"         => "Single",
)
