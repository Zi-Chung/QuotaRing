namespace QuotaRing;

internal sealed class SlotEditorForm : Form
{
    private readonly TextBox _nameBox;
    private readonly TextBox _badgeBox;
    private readonly TextBox _tierBox;
    private readonly ComboBox _windowCombo;
    private readonly NumericUpDown _percentNum;
    private readonly DateTimePicker _resetPicker;

    public string SlotId { get; private set; } = "cursor";
    public string SlotName => _nameBox.Text.Trim();
    public string SlotBadge => _badgeBox.Text.Trim();
    public string SlotTier => _tierBox.Text.Trim();
    public string WindowKind => _windowCombo.SelectedIndex switch
    {
        0 => "5h",
        1 => "weekly",
        _ => "monthly"
    };
    public double RemainingPercent => (double)_percentNum.Value;
    public DateTimeOffset ResetDate => new(_resetPicker.Value);

    public SlotEditorForm()
    {
        Text = "QuotaRing · 添加/更新开放插槽";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(360, 290);
        TopMost = true;

        var presetRow = new FlowLayoutPanel { Left = 14, Top = 12, Width = 332, Height = 28 };
        presetRow.Controls.Add(MakePresetButton("Cursor (月)", () => ApplyPreset("cursor", "Cursor", "Cu", "Pro", 2, TimeSpan.FromDays(30))));
        presetRow.Controls.Add(MakePresetButton("GrokBot (5h)", () => ApplyPreset("grokbot", "GrokBot", "G", "SuperGrok", 0, TimeSpan.FromHours(5))));
        presetRow.Controls.Add(MakePresetButton("Claude (周)", () => ApplyPreset("claude", "Claude", "Cl", "Pro", 1, TimeSpan.FromDays(7))));
        Controls.Add(presetRow);

        Controls.Add(new Label { Text = "品牌名称:", Left = 16, Top = 52, Width = 72 });
        _nameBox = new TextBox { Left = 96, Top = 48, Width = 110, Text = "Cursor" };
        _nameBox.TextChanged += (_, _) =>
        {
            string clean = new string(_nameBox.Text.ToLowerInvariant().Where(c => char.IsLetterOrDigit(c) || c == '-' || c == '_').ToArray());
            if (!string.IsNullOrEmpty(clean)) SlotId = clean;
        };
        Controls.Add(_nameBox);

        Controls.Add(new Label { Text = "缩写:", Left = 216, Top = 52, Width = 40 });
        _badgeBox = new TextBox { Left = 258, Top = 48, Width = 86, MaxLength = 2, Text = "Cu" };
        Controls.Add(_badgeBox);

        Controls.Add(new Label { Text = "套餐方案:", Left = 16, Top = 88, Width = 72 });
        _tierBox = new TextBox { Left = 96, Top = 84, Width = 248, Text = "Pro" };
        Controls.Add(_tierBox);

        Controls.Add(new Label { Text = "额度周期:", Left = 16, Top = 124, Width = 72 });
        _windowCombo = new ComboBox
        {
            Left = 96,
            Top = 120,
            Width = 248,
            DropDownStyle = ComboBoxStyle.DropDownList
        };
        _windowCombo.Items.AddRange(new object[] { "5 小时额度 (5)", "周额度 · 7天 (W)", "月额度 · 30天 (M)" });
        _windowCombo.SelectedIndex = 2;
        Controls.Add(_windowCombo);

        Controls.Add(new Label { Text = "剩余比例 %:", Left = 16, Top = 160, Width = 76 });
        _percentNum = new NumericUpDown
        {
            Left = 96,
            Top = 156,
            Width = 100,
            Minimum = 0,
            Maximum = 100,
            DecimalPlaces = 0,
            Value = 80
        };
        Controls.Add(_percentNum);

        Controls.Add(new Label { Text = "重置时间:", Left = 16, Top = 196, Width = 72 });
        _resetPicker = new DateTimePicker
        {
            Left = 96,
            Top = 192,
            Width = 248,
            Format = DateTimePickerFormat.Custom,
            CustomFormat = "yyyy-MM-dd HH:mm",
            Value = DateTime.Now.AddDays(30)
        };
        Controls.Add(_resetPicker);

        var saveBtn = new Button
        {
            Text = "保存插槽",
            Left = 176,
            Top = 242,
            Width = 82,
            Height = 30,
            DialogResult = DialogResult.OK
        };
        var cancelBtn = new Button
        {
            Text = "取消",
            Left = 264,
            Top = 242,
            Width = 80,
            Height = 30,
            DialogResult = DialogResult.Cancel
        };
        Controls.Add(saveBtn);
        Controls.Add(cancelBtn);
        AcceptButton = saveBtn;
        CancelButton = cancelBtn;
    }

    private static Button MakePresetButton(string text, Action onClick)
    {
        var btn = new Button { Text = text, AutoSize = true, Height = 24, Margin = new Padding(0, 0, 6, 0) };
        btn.Click += (_, _) => onClick();
        return btn;
    }

    private void ApplyPreset(string id, string name, string badge, string tier, int windowIdx, TimeSpan offset)
    {
        SlotId = id;
        _nameBox.Text = name;
        _badgeBox.Text = badge;
        _tierBox.Text = tier;
        _windowCombo.SelectedIndex = windowIdx;
        _resetPicker.Value = DateTime.Now.Add(offset);
    }
}
