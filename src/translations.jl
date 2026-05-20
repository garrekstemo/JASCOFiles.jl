"""
Japanese→English mappings for JASCO footer metadata.

JASCO FTIR and V-series UV-Vis exports embed footer keys (and a small set of
values) in Japanese. The parser stores the original Japanese key untouched and
adds an English-aliased entry resolving to the same value, so callers can use
either string.

Adding a missing entry is a one-line PR — append to the appropriate dict.
"""

JAPANESE_KEY_TRANSLATIONS = Dict{String,String}(
    "試料名"           => "Sample name",
    "コメント"         => "Comment",
    "測定者"           => "Measurer",
    "所属"             => "Affiliation",
    "会社"             => "Company",
    "オペレーター"     => "Operator",
    "作成日時"         => "Creation date",
    "データタイプ"     => "Data array type",
    "横軸"             => "Horizontal axis",
    "縦軸"             => "Vertical axis",
    "スタート"         => "Start",
    "エンド"           => "End",
    "データ間隔"       => "Data interval",
    "データ数"         => "Data points",
    "機種名"           => "Model Name",
    "シリアル番号"     => "Serial Number",
    "測定日時"         => "Measurement Date",
    "光源"             => "Light source",
    "光源切換"         => "Light source change wavelength",
    "検出器"           => "Detector",
    "積算回数"         => "Accumulation",
    "分解"             => "Resolution",
    "ゼロフィリング"   => "Zero-filling",
    "アポダイゼーション" => "Apodization",
    "ゲイン"           => "Gain",
    "アパーチャー"     => "Aperture",
    "スキャンスピード" => "Scan speed",
    "フィルタ"         => "Filter",
    "測光モード"       => "Photometric mode",
    "UV/Vis バンド幅"  => "UV/Vis bandwidth",
    "レスポンス"       => "Response",
    "走査速度"         => "Scan speed",
    "付属品名"         => "Accessory name",
)

JAPANESE_VALUE_TRANSLATIONS = Dict{String,String}(
    "等間隔データ"     => "Equally-spaced data",
    "標準光源"         => "Standard light source",
    "自動"             => "Automatic",
)
