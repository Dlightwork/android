using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace ZapretGlassGui;

public partial class Form1 : Form
{
    // Disable painting for performance during initialization
    private const int WM_SETREDRAW = 0x000B;

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    private readonly System.Windows.Forms.Timer _statusTimer = new() { Interval = 1200 };
    private readonly List<string> _tempFiles = new();
    private readonly Dictionary<string, Button> _navButtons = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, Panel> _pages = new(StringComparer.OrdinalIgnoreCase);

    private Process? _runnerProcess;
    private string _rootDir = string.Empty;
    private string _enginePath = string.Empty;
    private string _runnerPath = string.Empty;
    private string _basePresetPath = string.Empty;

    private readonly bool _isAdmin;
    private bool _darkTheme = true;
    private bool _redTheme;
    private bool _greenTheme;
    private string _themeMode = "dark";
    private string _activePage = "dashboard";
    private string _runState = "idle";
    private string _runMode = "-";
    private bool _runtimeInitStarted;

    private GradientPanel _background = null!;
    private GlassPanel _surface = null!;
    private GlassPanel _sidebar = null!;
    private Panel _contentHost = null!;
    private TextBox _logBox = null!;
    private TextBox _miniLogBox = null!;
    private NorknLogoControl _titleLogo = null!;

    private Button _btnStartMulti = null!;
    private Button _btnStartStrong = null!;
    private Button _btnStop = null!;
    private Button _btnDiag = null!;
    private Button _btnOpenFolder = null!;
    private Button _btnOpenPreset = null!;
    private Button _btnOpenLists = null!;
    private Button _btnMin = null!;
    private Button _btnMax = null!;
    private Button _btnClose = null!;
    private Button _btnInstallService = null!;
    private Button _btnRemoveService = null!;

    private Label _lblStatus = null!;
    private Label _lblStatusHint = null!;
    private Label _lblMode = null!;
    private Label _lblPid = null!;
    private Label _lblRunSummary = null!;
    private Label _lblServiceState = null!;
    private Panel _statusDot = null!;

    private ComboBox _cmbTheme = null!;
    private CheckBox _chkSupplement = null!;
    private CheckBox _chkAutoLists = null!;
    private CheckBox _chkHidden = null!;

    private const string ServiceTaskName = "NoRKNBypassService";

    // Template colors - dark theme
    private static readonly Color DarkBg0 = Color.FromArgb(20, 24, 28);
    private static readonly Color DarkBg1 = Color.FromArgb(24, 28, 33);
    private static readonly Color DarkFg0 = Color.FromArgb(238, 242, 246);
    private static readonly Color DarkFg1 = Color.FromArgb(167, 177, 190);
    private static readonly Color DarkGlass = Color.FromArgb(176, 34, 39, 45);
    private static readonly Color DarkGlass2 = Color.FromArgb(196, 29, 34, 40);
    private static readonly Color DarkStroke = Color.FromArgb(72, 95, 107, 122);
    private static readonly Color DarkAccent = Color.FromArgb(58, 157, 245);
    
    // Light theme colors
    private static readonly Color LightBg0 = Color.FromArgb(244, 246, 255);
    private static readonly Color LightFg0 = Color.FromArgb(0, 0, 0);
    private static readonly Color LightFg1 = Color.FromArgb(0, 0, 0);
    private static readonly Color LightGlass = Color.FromArgb(60, 255, 255, 255);
    private static readonly Color LightGlass2 = Color.FromArgb(40, 255, 255, 255);
    private static readonly Color LightStroke = Color.FromArgb(20, 0, 0, 255);
    private static readonly Color LightAccent = Color.FromArgb(43, 116, 255);

    // Red theme colors
    private static readonly Color RedBg0 = Color.FromArgb(45, 10, 16);
    private static readonly Color RedBg1 = Color.FromArgb(85, 18, 28);
    private static readonly Color RedFg0 = Color.FromArgb(255, 241, 241);
    private static readonly Color RedFg1 = Color.FromArgb(243, 199, 199);
    private static readonly Color RedGlass = Color.FromArgb(18, 255, 140, 140);
    private static readonly Color RedGlass2 = Color.FromArgb(12, 255, 120, 120);
    private static readonly Color RedStroke = Color.FromArgb(46, 255, 140, 140);
    private static readonly Color RedAccent = Color.FromArgb(226, 74, 74);

    // Green theme colors
    private static readonly Color GreenBg0 = Color.FromArgb(10, 34, 20);
    private static readonly Color GreenBg1 = Color.FromArgb(18, 70, 41);
    private static readonly Color GreenFg0 = Color.FromArgb(236, 255, 243);
    private static readonly Color GreenFg1 = Color.FromArgb(186, 232, 201);
    private static readonly Color GreenGlass = Color.FromArgb(18, 120, 255, 170);
    private static readonly Color GreenGlass2 = Color.FromArgb(12, 100, 230, 150);
    private static readonly Color GreenStroke = Color.FromArgb(46, 120, 255, 170);
    private static readonly Color GreenAccent = Color.FromArgb(64, 186, 118);

    public Form1(bool isAdmin)
    {
        _isAdmin = isAdmin;
        InitializeComponent();
        
        // Отключить отрисовку полностью на уровне Windows при инициализации
        if (IsHandleCreated)
        {
            SendMessage(Handle, WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero);
        }
        
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        UpdateStyles();
        LoadThemeSetting();
        BuildUi();
        ApplyTheme();
        SetRuntimeControlsEnabled(false);
        ShowPage("dashboard");

        _statusTimer.Tick += (_, _) => PollRunner();
        _statusTimer.Start();
    }

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            // Не показывать окно при создании - оно появится только в OnShown
            cp.Style &= ~0x10000000;  // WS_VISIBLE
            return cp;
        }
    }

    protected override void OnLoad(EventArgs e)
    {
        base.OnLoad(e);
        // Убедиться что окно скрыто при загрузке
        Hide();
        // Отключить отрисовку
        if (IsHandleCreated)
        {
            SendMessage(Handle, WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero);
            SuspendLayout();
        }
    }

    private void SetThemeMode(string mode, bool persist)
    {
        var normalized = (mode ?? "dark").Trim().ToLowerInvariant();
        if (!IsSupportedTheme(normalized))
        {
            normalized = "dark";
        }

        _themeMode = normalized;
        _redTheme = normalized == "red";
        _greenTheme = normalized == "green";
        _darkTheme = normalized != "light";

        if (persist)
        {
            SaveThemeSetting();
        }
    }

    private void LoadThemeSetting()
    {
        try
        {
            var settingsPath = GetSettingsPath();
            if (!File.Exists(settingsPath))
            {
                SetThemeMode("dark", false);
                return;
            }

            var json = File.ReadAllText(settingsPath, Encoding.UTF8);
            var settings = JsonSerializer.Deserialize<UiSettings>(json);
            SetThemeMode(settings?.Theme ?? "dark", false);
        }
        catch
        {
            SetThemeMode("dark", false);
        }
    }

    private void SaveThemeSetting()
    {
        try
        {
            var settingsPath = GetSettingsPath();
            var settingsDir = Path.GetDirectoryName(settingsPath);
            if (!string.IsNullOrWhiteSpace(settingsDir))
            {
                Directory.CreateDirectory(settingsDir);
            }

            var json = JsonSerializer.Serialize(new UiSettings { Theme = _themeMode });
            File.WriteAllText(settingsPath, json, Encoding.UTF8);
        }
        catch
        {
            // ignore save errors
        }
    }

    private static bool IsSupportedTheme(string theme) =>
        theme is "dark" or "light" or "red" or "green";

    private static string GetSettingsPath()
    {
        var baseDir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(baseDir, "NoRKN", "settings.json");
    }

    private sealed class UiSettings
    {
        public string Theme { get; set; } = "dark";
    }

    protected override void OnShown(EventArgs e)
    {
        // Включить отрисовку и показать полностью готовую форму
        if (IsHandleCreated)
        {
            SendMessage(Handle, WM_SETREDRAW, new IntPtr(1), IntPtr.Zero);
        }
        
        ResumeLayout(true);
        Show();
        BringToFront();
        Refresh();
        
        base.OnShown(e);
        
        ApplyRoundMask();
        SyncMaxButton();
        if (!_runtimeInitStarted)
        {
            _runtimeInitStarted = true;
            BeginInvoke(new Action(InitRuntime));
        }
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        ApplyRoundMask();
        SyncMaxButton();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        _statusTimer.Stop();
        StopProfile(true);
        base.OnFormClosing(e);
    }

    private void BuildUi()
    {
        Controls.Clear();

        _background = new GradientPanel { Dock = DockStyle.Fill, Padding = new Padding(0) };
        Controls.Add(_background);

        _surface = new GlassPanel { Dock = DockStyle.Fill, Radius = 20, FillColor = Color.Transparent, BorderColor = Color.Transparent };
        _background.Controls.Add(_surface);

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            BackColor = Color.Transparent
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        _surface.Controls.Add(root);

        root.Controls.Add(BuildTitleBar(), 0, 0);
        root.Controls.Add(BuildMainArea(), 0, 1);
    }

    private Control BuildTitleBar()
    {
        var bar = new Panel { Dock = DockStyle.Fill, BackColor = Color.Transparent, Padding = new Padding(8, 6, 8, 4) };
        bar.MouseDown += TitleDrag_MouseDown;

        var leftBrand = new FlowLayoutPanel
        {
            Dock = DockStyle.Left,
            Width = 260,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.Transparent
        };
        leftBrand.MouseDown += TitleDrag_MouseDown;
        _titleLogo = new NorknLogoControl
        {
            Width = 20,
            Height = 20,
            Margin = new Padding(0, 5, 8, 0)
        };
        var appName = new Label
        {
            AutoSize = true,
            Text = "NoRKN",
            Font = new Font("Segoe UI", 12f, FontStyle.Bold),
            Tag = "primary",
            Margin = new Padding(0, 3, 0, 0)
        };
        appName.MouseDown += TitleDrag_MouseDown;
        leftBrand.Controls.Add(_titleLogo);
        leftBrand.Controls.Add(appName);
        bar.Controls.Add(leftBrand);

        var title = new Label
        {
            Dock = DockStyle.Fill,
            Text = "NoRKN",
            Font = new Font("Segoe UI", 10f, FontStyle.Regular),
            TextAlign = ContentAlignment.MiddleCenter,
            Tag = "secondary"
        };
        title.MouseDown += TitleDrag_MouseDown;
        bar.Controls.Add(title);

        var topButtons = new FlowLayoutPanel
        {
            Dock = DockStyle.Right,
            Width = 144,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.Transparent
        };
        _btnMin = SmallButton("_");
        _btnMin.Click += (_, _) => WindowState = FormWindowState.Minimized;
        _btnMax = SmallButton("□");
        _btnMax.Click += (_, _) => ToggleWindowState();
        _btnClose = SmallButton("x");
        _btnClose.Click += (_, _) => Close();
        topButtons.Controls.Add(_btnMin);
        topButtons.Controls.Add(_btnMax);
        topButtons.Controls.Add(_btnClose);
        bar.Controls.Add(topButtons);

        return bar;
    }

    private Control BuildMainArea()
    {
        var split = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            BackColor = Color.Transparent,
            Padding = new Padding(10, 6, 10, 6)
        };
        split.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 290));
        split.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        _sidebar = BuildSidebar();
        split.Controls.Add(_sidebar, 0, 0);

        _contentHost = new Panel { Dock = DockStyle.Fill, BackColor = Color.Transparent, Padding = new Padding(12, 0, 0, 0) };
        split.Controls.Add(_contentHost, 1, 0);

        BuildPages();
        return split;
    }

    private GlassPanel BuildSidebar()
    {
        var panel = new GlassPanel { Dock = DockStyle.Fill, Radius = 14, Padding = new Padding(10, 12, 10, 10) };
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            BackColor = Color.Transparent
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        panel.Controls.Add(root);

        var brandRow = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            AutoSize = true,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 0, 0, 8)
        };
        brandRow.Controls.Add(MakeLabel("NoRKN", 17f, true, false));
        root.Controls.Add(brandRow, 0, 0);

        var stack = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoScroll = true,
            BackColor = Color.Transparent
        };
        root.Controls.Add(stack, 0, 1);

        stack.Controls.Add(MakeLabel("Меню", 14f, true, false));
        AddNav(stack, "dashboard", "ГЛАВНАЯ", "Профили и статус", "⌂");
        AddNav(stack, "settings", "НАСТРОЙКИ", "Тема и параметры", "⚙");

        return panel;
    }

    private void AddNav(FlowLayoutPanel stack, string key, string title, string hint, string icon)
    {
        var btn = new Button
        {
            Width = 240,
            Height = 40,
            Text = $"{icon}  {title}",
            TextAlign = ContentAlignment.MiddleLeft,
            Padding = new Padding(16, 0, 0, 0),
            FlatStyle = FlatStyle.Flat,
            Cursor = Cursors.Hand,
            Tag = "nav",
            Margin = new Padding(0, 8, 0, 0),
            Font = new Font("Segoe UI", 10f, FontStyle.Bold),
            AutoEllipsis = true
        };
        btn.FlatAppearance.BorderSize = 0;
        btn.Click += (_, _) => ShowPage(key);
        _navButtons[key] = btn;
        stack.Controls.Add(btn);

        var hintLabel = new Label
        {
            AutoSize = false,
            Width = 240,
            Height = 22,
            Text = hint,
            Font = new Font("Segoe UI", 11f, FontStyle.Regular),
            Tag = "secondary",
            Padding = new Padding(16, 2, 4, 0),
            Margin = new Padding(0, 0, 0, 0),
            TextAlign = ContentAlignment.TopLeft,
            AutoEllipsis = true
        };
        stack.Controls.Add(hintLabel);
    }

    private void BuildPages()
    {
        _pages["dashboard"] = BuildDashboardPage();
        _pages["settings"] = BuildSettingsPage();

        foreach (var page in _pages.Values)
        {
            page.Dock = DockStyle.Fill;
            page.Visible = false;
            _contentHost.Controls.Add(page);
        }
    }

    private Panel BuildDashboardPage()
    {
        var page = new Panel { BackColor = Color.Transparent, AutoScroll = true };
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 6,
            BackColor = Color.Transparent,
            Padding = new Padding(0, 0, 0, 6)
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 176));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 150));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 104));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 78));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        page.Controls.Add(root);

        var headerPanel = new Panel
        {
            Dock = DockStyle.Fill,
            Height = 70,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 0, 0, 8)
        };
        var headerStack = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoScroll = false,
            BackColor = Color.Transparent
        };
        headerPanel.Controls.Add(headerStack);
        headerStack.Controls.Add(MakeLabel("Главная", 23f, true, false));
        var headSub = MakeLabel("Состояние NoRKN", 11f, false, true);
        headSub.Margin = new Padding(0, 2, 0, 0);
        headerStack.Controls.Add(headSub);
        root.Controls.Add(headerPanel, 0, 0);

        GlassPanel BuildValueCard(string title, string value, string hint, Padding margin)
        {
            var card = new GlassPanel
            {
                Dock = DockStyle.Fill,
                Radius = 12,
                Padding = new Padding(18, 14, 18, 12),
                Margin = margin
            };
            var stack = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.TopDown,
                WrapContents = false,
                BackColor = Color.Transparent
            };
            stack.Controls.Add(MakeLabel(title, 12f, false, true));
            var valueLabel = MakeLabel(value, 20f, true, false);
            valueLabel.Margin = new Padding(0, 3, 0, 0);
            stack.Controls.Add(valueLabel);
            var hintLabel = MakeLabel(hint, 10.5f, false, true);
            hintLabel.Margin = new Padding(0, 2, 0, 0);
            stack.Controls.Add(hintLabel);
            card.Controls.Add(stack);
            return card;
        }

        var cardGrid = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 0, 0, 8)
        };
        cardGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        cardGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        cardGrid.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.Controls.Add(cardGrid, 0, 1);

        var statusCard = new GlassPanel
        {
            Dock = DockStyle.Fill,
            Radius = 12,
            Padding = new Padding(18, 14, 18, 12),
            Margin = new Padding(0, 0, 8, 0)
        };
        var statusLayout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            BackColor = Color.Transparent
        };
        statusLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        statusLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        statusLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        statusLayout.Controls.Add(MakeLabel("Статус NoRKN", 12f, false, true), 0, 0);
        _lblStatus = MakeLabel("Ожидание", 20f, true, false);
        _lblStatus.Margin = new Padding(0, 3, 0, 0);
        statusLayout.Controls.Add(_lblStatus, 0, 1);
        _lblStatusHint = MakeLabel("Ожидает запуска", 10.5f, false, true);
        _lblStatusHint.Margin = new Padding(0, 2, 0, 0);
        statusLayout.Controls.Add(_lblStatusHint, 0, 2);
        statusCard.Controls.Add(statusLayout);
        cardGrid.Controls.Add(statusCard, 0, 0);

        cardGrid.Controls.Add(
            BuildValueCard("Автозапуск", "Отключён", "Запускайте вручную", new Padding(8, 0, 0, 0)),
            1,
            0);

        var launchCard = new GlassPanel
        {
            Dock = DockStyle.Fill,
            Radius = 12,
            Padding = new Padding(14, 10, 14, 10),
            Margin = new Padding(0, 0, 0, 8)
        };
        root.Controls.Add(launchCard, 0, 2);
        var launchLayout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            BackColor = Color.Transparent
        };
        launchLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        launchLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        launchCard.Controls.Add(launchLayout);
        launchLayout.Controls.Add(MakeLabel("Запуск профиля", 13f, true, false), 0, 0);

        var actions = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 2,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 6, 0, 0)
        };
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        actions.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
        actions.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));

        _btnStartMulti = ActionButton("Старт: multisplit", "primary", 240);
        _btnStartMulti.Click += (_, _) => StartProfile("multisplit");
        _btnStartStrong = ActionButton("Старт: STRONG", "primary", 240);
        _btnStartStrong.Click += (_, _) => StartProfile("strong");
        _btnStop = ActionButton("Остановить", "ghost", 240);
        _btnStop.Click += (_, _) => StopProfile(false);
        _btnDiag = ActionButton("Диагностика", "ghost", 240);
        _btnDiag.Click += (_, _) => RunDiag();

        _btnStartMulti.Dock = DockStyle.Fill;
        _btnStartStrong.Dock = DockStyle.Fill;
        _btnStop.Dock = DockStyle.Fill;
        _btnDiag.Dock = DockStyle.Fill;
        _btnStartMulti.Margin = new Padding(0, 0, 6, 6);
        _btnStartStrong.Margin = new Padding(6, 0, 0, 6);
        _btnStop.Margin = new Padding(0, 0, 6, 0);
        _btnDiag.Margin = new Padding(6, 0, 0, 0);

        actions.Controls.Add(_btnStartMulti, 0, 0);
        actions.Controls.Add(_btnStartStrong, 1, 0);
        actions.Controls.Add(_btnStop, 0, 1);
        actions.Controls.Add(_btnDiag, 1, 1);
        launchLayout.Controls.Add(actions, 0, 1);

        var quickCard = new GlassPanel
        {
            Dock = DockStyle.Fill,
            Radius = 12,
            Padding = new Padding(14, 10, 14, 10),
            Margin = new Padding(0, 0, 0, 8)
        };
        root.Controls.Add(quickCard, 0, 3);
        var quickLayout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            BackColor = Color.Transparent
        };
        quickLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        quickLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        quickCard.Controls.Add(quickLayout);
        quickLayout.Controls.Add(MakeLabel("Быстрые действия", 13f, true, false), 0, 0);

        var quickButtons = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 1,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 6, 0, 0)
        };
        quickButtons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.333f));
        quickButtons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.333f));
        quickButtons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.334f));

        _btnOpenFolder = ActionButton("Открыть папку", "ghost", 180);
        _btnOpenFolder.Click += (_, _) => OpenFolder();
        _btnOpenPreset = ActionButton("Открыть пресет", "ghost", 180);
        _btnOpenPreset.Click += (_, _) => OpenPreset();
        _btnOpenLists = ActionButton("Открыть списки", "ghost", 180);
        _btnOpenLists.Click += (_, _) => OpenLists();

        _btnOpenFolder.Dock = DockStyle.Fill;
        _btnOpenPreset.Dock = DockStyle.Fill;
        _btnOpenLists.Dock = DockStyle.Fill;
        _btnOpenFolder.Margin = new Padding(0, 0, 6, 0);
        _btnOpenPreset.Margin = new Padding(3, 0, 3, 0);
        _btnOpenLists.Margin = new Padding(6, 0, 0, 0);

        quickButtons.Controls.Add(_btnOpenFolder, 0, 0);
        quickButtons.Controls.Add(_btnOpenPreset, 1, 0);
        quickButtons.Controls.Add(_btnOpenLists, 2, 0);
        quickLayout.Controls.Add(quickButtons, 0, 1);

        var stateCard = new GlassPanel
        {
            Dock = DockStyle.Fill,
            Radius = 12,
            Padding = new Padding(14, 10, 14, 8),
            Margin = new Padding(0, 0, 0, 8)
        };
        root.Controls.Add(stateCard, 0, 4);
        var stateLayout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            BackColor = Color.Transparent
        };
        stateLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        stateLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        stateCard.Controls.Add(stateLayout);

        var stateLine = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            AutoSize = true,
            BackColor = Color.Transparent,
            Margin = new Padding(0)
        };
        _statusDot = new Panel { Width = 12, Height = 12, Margin = new Padding(0, 3, 8, 0) };
        _lblRunSummary = MakeLabel("DPI не запущен", 11f, false, false);
        stateLine.Controls.Add(_statusDot);
        stateLine.Controls.Add(_lblRunSummary);
        stateLayout.Controls.Add(stateLine, 0, 0);

        var metaLine = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 2, 0, 0)
        };
        _lblMode = MakeLabel("Режим: -", 10.5f, false, true);
        _lblMode.Margin = new Padding(0, 0, 14, 0);
        _lblPid = MakeLabel("Runner PID: -", 10.5f, false, true);
        metaLine.Controls.Add(_lblMode);
        metaLine.Controls.Add(_lblPid);
        stateLayout.Controls.Add(metaLine, 0, 1);

        var logCard = new GlassPanel
        {
            Dock = DockStyle.Fill,
            Radius = 12,
            Padding = new Padding(14, 10, 14, 12),
            Margin = new Padding(0)
        };
        root.Controls.Add(logCard, 0, 5);
        var logLayout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            BackColor = Color.Transparent
        };
        logLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        logLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        logCard.Controls.Add(logLayout);
        logLayout.Controls.Add(MakeLabel("Статус", 14f, true, false), 0, 0);

        var miniLog = new TextBox
        {
            Dock = DockStyle.Fill,
            Multiline = true,
            ScrollBars = ScrollBars.Vertical,
            ReadOnly = true,
            Font = new Font("Consolas", 10.5f),
            BackColor = Color.FromArgb(18, 21, 26),
            ForeColor = Color.FromArgb(206, 215, 228),
            BorderStyle = BorderStyle.FixedSingle,
            Margin = new Padding(0, 8, 0, 0)
        };
        logLayout.Controls.Add(miniLog, 0, 1);
        _miniLogBox = miniLog;
        _logBox = miniLog;

        return page;
    }

    private Panel BuildSettingsPage()
    {
        var page = new Panel { BackColor = Color.Transparent };
        var card = new GlassPanel { Dock = DockStyle.Top, Height = 440, Radius = 16, Padding = new Padding(18, 16, 18, 16) };
        page.Controls.Add(card);

        var stack = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            BackColor = Color.Transparent
        };
        card.Controls.Add(stack);
        stack.Controls.Add(MakeLabel("Настройки", 20f, true, false));
        stack.Controls.Add(MakeLabel("Тема и параметры запуска", 12f, false, true));

        var themeRow = new FlowLayoutPanel
        {
            Width = 480,
            Height = 36,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 16, 0, 0)
        };
        themeRow.Controls.Add(MakeLabel("Тема:", 12f, false, false));
        _cmbTheme = new ComboBox { Width = 150, DropDownStyle = ComboBoxStyle.DropDownList, Margin = new Padding(10, 0, 0, 0) };
        _cmbTheme.Items.AddRange(new object[] { "dark", "light", "red", "green" });
        _cmbTheme.SelectedItem = _themeMode;
        if (_cmbTheme.SelectedIndex < 0)
        {
            _cmbTheme.SelectedItem = "dark";
        }
        _cmbTheme.SelectedIndexChanged += (_, _) =>
        {
            var selectedTheme = (_cmbTheme.SelectedItem?.ToString() ?? "dark").ToLowerInvariant();
            SetThemeMode(selectedTheme, true);
            ApplyTheme();
            AppendLog($"[ui] theme set to {_cmbTheme.SelectedItem}");
        };
        themeRow.Controls.Add(_cmbTheme);
        stack.Controls.Add(themeRow);

        _chkSupplement = new CheckBox { Text = "Включить Roblox-дополнение", Checked = true, AutoSize = true, Tag = "checkbox", Margin = new Padding(0, 16, 0, 0) };
        _chkAutoLists = new CheckBox { Text = "Использовать авто host/ip списки", Checked = true, AutoSize = true, Tag = "checkbox", Margin = new Padding(0, 8, 0, 0) };
        _chkHidden = new CheckBox { Text = "Запускать helper скрыто", Checked = true, AutoSize = true, Tag = "checkbox", Margin = new Padding(0, 8, 0, 0) };
        stack.Controls.Add(_chkSupplement);
        stack.Controls.Add(_chkAutoLists);
        stack.Controls.Add(_chkHidden);

        stack.Controls.Add(MakeLabel("Все запуски идут через tools/run-winws2-preset.ps1 и базовый preset.", 12f, false, true));

        stack.Controls.Add(MakeLabel("Автозапуск обхода (служба)", 12f, true, false));
        _lblServiceState = MakeLabel("Состояние: неизвестно", 11f, false, true);
        _lblServiceState.Margin = new Padding(0, 8, 0, 0);
        stack.Controls.Add(_lblServiceState);

        var serviceRow = new FlowLayoutPanel
        {
            Width = 560,
            Height = 38,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 8, 0, 0)
        };
        _btnInstallService = ActionButton("Установить автозапуск", "primary", 250);
        _btnInstallService.Click += (_, _) => InstallServiceAutostart();
        _btnRemoveService = ActionButton("Удалить автозапуск", "ghost", 250);
        _btnRemoveService.Click += (_, _) => RemoveServiceAutostart();
        serviceRow.Controls.Add(_btnInstallService);
        serviceRow.Controls.Add(_btnRemoveService);
        stack.Controls.Add(serviceRow);

        stack.Controls.Add(MakeLabel("После установки обход будет запускаться в фоне при старте Windows.", 10.5f, false, true));
        return page;
    }

    private Panel BuildLogsPage()
    {
        var page = new Panel { BackColor = Color.Transparent };
        var card = new GlassPanel { Dock = DockStyle.Fill, Radius = 16, Padding = new Padding(18, 16, 18, 16) };
        page.Controls.Add(card);

        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            BackColor = Color.Transparent
        };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        card.Controls.Add(layout);
        layout.Controls.Add(MakeLabel("Логи", 20f, true, false), 0, 0);

        var actions = new FlowLayoutPanel
        {
            Width = 380,
            Height = 40,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 12, 0, 12)
        };
        var clear = ActionButton("Очистить", "ghost", 120);
        clear.Click += (_, _) => _logBox?.Clear();
        var save = ActionButton("Сохранить в файл...", "ghost", 170);
        save.Click += (_, _) => SaveLogs();
        actions.Controls.Add(clear);
        actions.Controls.Add(save);
        layout.Controls.Add(actions, 0, 1);

        var fullLogBox = new TextBox
        {
            Dock = DockStyle.Fill,
            Multiline = true,
            ScrollBars = ScrollBars.Vertical,
            ReadOnly = true,
            Font = new Font("Consolas", 10f),
            BorderStyle = BorderStyle.FixedSingle,
            BackColor = Color.FromArgb(20, 23, 32),
            ForeColor = Color.FromArgb(194, 204, 224)
        };
        layout.Controls.Add(fullLogBox, 0, 2);
        
        // Use the same log box as dashboard
        _logBox = fullLogBox;
        return page;
    }

    private Panel BuildAboutPage()
    {
        var page = new Panel { BackColor = Color.Transparent };
        var card = new GlassPanel { Dock = DockStyle.Top, Height = 280, Radius = 16, Padding = new Padding(18, 16, 18, 16) };
        page.Controls.Add(card);
        var stack = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            BackColor = Color.Transparent
        };
        card.Controls.Add(stack);
        stack.Controls.Add(MakeLabel("About", 20f, true, false));
        stack.Controls.Add(MakeLabel("Интерфейс перенесен из вашего glass_gui_template в .NET WinForms.", 12f, false, true));
        stack.Controls.Add(MakeLabel("Подключены профили multisplit/strong, логи и автосписки.", 12f, false, true));
        return page;
    }

    private Label MakeLabel(string text, float size, bool semibold, bool secondary)
    {
        return new Label
        {
            AutoSize = true,
            MaximumSize = new Size(1200, 0),
            Text = text,
            Font = new Font("Segoe UI", size, semibold ? FontStyle.Bold : FontStyle.Regular),
            Tag = secondary ? "secondary" : "primary",
            Margin = new Padding(0)
        };
    }

    private Button SmallButton(string text)
    {
        var b = new Button
        {
            Width = 40,
            Height = 32,
            Text = text,
            FlatStyle = FlatStyle.Flat,
            Tag = "window",
            Cursor = Cursors.Hand,
            Margin = new Padding(3, 0, 0, 0),
            Font = new Font("Segoe UI", 11f, FontStyle.Bold),
            TextAlign = ContentAlignment.MiddleCenter
        };
        b.FlatAppearance.BorderSize = 0;
        return b;
    }

    private Button ActionButton(string text, string role, int width)
    {
        var b = new Button
        {
            Text = text,
            Width = width,
            Height = 32,
            FlatStyle = FlatStyle.Flat,
            Tag = role,
            Cursor = Cursors.Hand,
            Margin = new Padding(0, 0, 8, 0),
            Font = new Font("Segoe UI", 10f, FontStyle.Bold),
            TextAlign = ContentAlignment.MiddleCenter,
            AutoEllipsis = true
        };
        b.FlatAppearance.BorderSize = 0;
        return b;
    }

    private void ShowPage(string key)
    {
        if (!_pages.TryGetValue(key, out var page))
        {
            return;
        }

        foreach (var p in _pages.Values)
        {
            p.Visible = false;
        }

        page.Visible = true;
        page.BringToFront();
        _activePage = key;
        UpdateNavStyle();
    }

    private void UpdateNavStyle()
    {
        var textPrimary = _greenTheme ? GreenFg0 : (_redTheme ? RedFg0 : (_darkTheme ? DarkFg0 : LightFg0));
        var selectedBg = _greenTheme
            ? Color.FromArgb(165, 36, 84, 57)
            : (_redTheme ? Color.FromArgb(165, 103, 32, 43) : (_darkTheme ? Color.FromArgb(170, 54, 63, 75) : Color.FromArgb(150, 210, 226, 255)));
        var selectedBorder = _greenTheme
            ? Color.FromArgb(110, 120, 255, 170)
            : (_redTheme ? Color.FromArgb(120, 255, 120, 120) : (_darkTheme ? Color.FromArgb(120, 118, 179, 255) : Color.FromArgb(150, 135, 173, 235)));
        var normalBg = _greenTheme
            ? Color.FromArgb(32, 18, 42, 30)
            : (_redTheme ? Color.FromArgb(32, 42, 16, 23) : (_darkTheme ? Color.FromArgb(38, 20, 24, 29) : Color.FromArgb(44, 255, 255, 255)));
        var normalBorder = _greenTheme
            ? Color.FromArgb(36, 50, 95, 72)
            : (_redTheme ? Color.FromArgb(36, 96, 42, 52) : (_darkTheme ? Color.FromArgb(36, 58, 64, 72) : Color.FromArgb(70, 200, 215, 235)));
        
        foreach (var kv in _navButtons)
        {
            var selected = kv.Key == _activePage;
            if (selected)
            {
                kv.Value.BackColor = selectedBg;
                kv.Value.FlatAppearance.BorderColor = selectedBorder;
                kv.Value.FlatAppearance.BorderSize = 1;
            }
            else
            {
                kv.Value.BackColor = normalBg;
                kv.Value.FlatAppearance.BorderColor = normalBorder;
                kv.Value.FlatAppearance.BorderSize = 0;
            }
            kv.Value.ForeColor = textPrimary;
        }
    }

    private void ApplyTheme()
    {
        _background.DarkTheme = _darkTheme;
        _background.RedTheme = _redTheme;
        _background.GreenTheme = _greenTheme;
        
        _surface.FillColor = Color.Transparent;
        _surface.BorderColor = Color.Transparent;
        
        _sidebar.FillColor = _greenTheme ? GreenGlass2 : (_redTheme ? RedGlass2 : (_darkTheme ? DarkGlass2 : LightGlass2));
        _sidebar.BorderColor = _greenTheme ? GreenStroke : (_redTheme ? RedStroke : (_darkTheme ? DarkStroke : LightStroke));

        ApplyColors(this);
        UpdateNavStyle();
        UpdateStatusColor();
        Refresh();
    }

    private void ApplyColors(Control c)
    {
        var textPrimary = _greenTheme ? GreenFg0 : (_redTheme ? RedFg0 : (_darkTheme ? DarkFg0 : LightFg0));
        var textSecondary = _greenTheme ? GreenFg1 : (_redTheme ? RedFg1 : (_darkTheme ? DarkFg1 : LightFg1));
        var ghostBg = _greenTheme
            ? Color.FromArgb(130, 30, 66, 46)
            : (_redTheme ? Color.FromArgb(130, 90, 24, 33) : (_darkTheme ? Color.FromArgb(170, 41, 47, 54) : Color.FromArgb(220, 236, 243, 255)));
        var ghostBorder = _greenTheme ? GreenStroke : (_redTheme ? RedStroke : (_darkTheme ? DarkStroke : LightStroke));
        var primaryBg = _greenTheme ? GreenAccent : (_redTheme ? RedAccent : (_darkTheme ? DarkAccent : LightAccent));
        var primaryBorder = _greenTheme ? GreenAccent : (_redTheme ? RedAccent : (_darkTheme ? DarkAccent : LightAccent));
        var windowBg = _greenTheme
            ? Color.FromArgb(110, 24, 56, 40)
            : (_redTheme ? Color.FromArgb(110, 72, 20, 28) : (_darkTheme ? Color.FromArgb(120, 43, 48, 55) : Color.FromArgb(210, 236, 243, 255)));
        var windowBorder = _greenTheme ? GreenStroke : (_redTheme ? RedStroke : (_darkTheme ? DarkStroke : LightStroke));
        var glass = _greenTheme ? GreenGlass : (_redTheme ? RedGlass : (_darkTheme ? DarkGlass : LightGlass));

        if (c is Label l)
        {
            l.ForeColor = (l.Tag as string) == "secondary" ? textSecondary : textPrimary;
        }
        else if (c is CheckBox ch)
        {
            ch.ForeColor = textPrimary;
            ch.BackColor = Color.Transparent;
        }
        else if (c is TextBox tb)
        {
            tb.BackColor = _greenTheme ? Color.FromArgb(14, 35, 25) : (_redTheme ? Color.FromArgb(34, 12, 17) : (_darkTheme ? Color.FromArgb(18, 21, 26) : Color.FromArgb(250, 252, 255)));
            tb.ForeColor = textPrimary;
            tb.BorderStyle = BorderStyle.FixedSingle;
        }
        else if (c is ComboBox cb)
        {
            cb.BackColor = _greenTheme ? Color.FromArgb(12, 30, 22) : (_redTheme ? Color.FromArgb(36, 14, 18) : (_darkTheme ? Color.FromArgb(20, 23, 32) : Color.FromArgb(245, 249, 255)));
            cb.ForeColor = textPrimary;
        }
        else if (c is Button b)
        {
            var role = b.Tag as string;
            var defaultBorder = _darkTheme ? Color.FromArgb(30, 30, 30) : Color.FromArgb(180, 180, 180);
            switch (role)
            {
                case "primary":
                    b.BackColor = primaryBg;
                    b.ForeColor = Color.White;
                    b.FlatAppearance.BorderColor = primaryBorder;
                    b.FlatAppearance.BorderSize = 1;
                    break;
                case "ghost":
                    b.BackColor = ghostBg;
                    b.ForeColor = textPrimary;
                    b.FlatAppearance.BorderColor = ghostBorder.A == 0 ? defaultBorder : ghostBorder;
                    b.FlatAppearance.BorderSize = 1;
                    break;
                case "window":
                    b.BackColor = windowBg;
                    b.ForeColor = textPrimary;
                    b.FlatAppearance.BorderColor = windowBorder.A == 0 ? defaultBorder : windowBorder;
                    b.FlatAppearance.BorderSize = 1;
                    break;
                case "nav":
                    break;
            }
        }
        else if (c is GlassPanel card && !ReferenceEquals(card, _surface) && !ReferenceEquals(card, _sidebar))
        {
            card.FillColor = glass;
            card.BorderColor = ghostBorder;
        }

        foreach (Control child in c.Controls)
        {
            ApplyColors(child);
        }
    }

    private void SetRuntimeControlsEnabled(bool enabled)
    {
        if (_btnStartMulti != null) _btnStartMulti.Enabled = enabled;
        if (_btnStartStrong != null) _btnStartStrong.Enabled = enabled;
        if (_btnStop != null) _btnStop.Enabled = enabled;
        if (_btnDiag != null) _btnDiag.Enabled = enabled;
        if (_btnOpenFolder != null) _btnOpenFolder.Enabled = enabled;
        if (_btnOpenPreset != null) _btnOpenPreset.Enabled = enabled;
        if (_btnOpenLists != null) _btnOpenLists.Enabled = enabled;
        if (_btnInstallService != null) _btnInstallService.Enabled = enabled;
        if (_btnRemoveService != null) _btnRemoveService.Enabled = enabled;
    }

    private void InitRuntime()
    {
        try
        {
            _rootDir = FindRoot();
            _enginePath = Path.Combine(_rootDir, "winws2.exe");
            _runnerPath = Path.Combine(_rootDir, "tools", "run-winws2-preset.ps1");
            _basePresetPath = Path.Combine(_rootDir, "presets", "all_tcp_udp_multisplit_sni.args");

            if (!File.Exists(_enginePath) || !File.Exists(_runnerPath) || !File.Exists(_basePresetPath))
            {
                throw new FileNotFoundException("Required winws2/preset files are missing in root.");
            }

            AppendLog("[app] ready");
            AppendLog($"[app] root: {_rootDir}");
            if (!_isAdmin)
            {
                AppendLog("[warning] App started without administrator rights. Start requires elevation.");
            }
            SetStatus("idle", "-", null);
            RefreshServiceState();
            SetRuntimeControlsEnabled(true);
        }
        catch (Exception ex)
        {
            AppendLog($"[error] {ex.Message}");
            MessageBox.Show(ex.Message, "NoRKN", MessageBoxButtons.OK, MessageBoxIcon.Error);
            SetRuntimeControlsEnabled(false);
        }
    }

    private static string FindRoot()
    {
        var candidates = new List<string>();
        static void Add(List<string> c, string? p)
        {
            if (string.IsNullOrWhiteSpace(p))
            {
                return;
            }

            var full = Path.GetFullPath(p);
            if (!c.Contains(full, StringComparer.OrdinalIgnoreCase))
            {
                c.Add(full);
            }
        }

        Add(candidates, Directory.GetCurrentDirectory());
        Add(candidates, AppContext.BaseDirectory);

        var probe = AppContext.BaseDirectory;
        for (var i = 0; i < 10; i++)
        {
            Add(candidates, probe);
            var parent = Directory.GetParent(probe);
            if (parent == null)
            {
                break;
            }

            probe = parent.FullName;
        }

        // Check for strong root - all files present
        bool IsStrongRoot(string c) =>
            File.Exists(Path.Combine(c, "winws2.exe")) &&
            Directory.Exists(Path.Combine(c, "tools")) &&
            Directory.Exists(Path.Combine(c, "presets"));

        // Check for acceptable root - at least exe present
        bool IsAcceptableRoot(string c) =>
            File.Exists(Path.Combine(c, "winws2.exe")) ||
            File.Exists(Path.Combine(c, "NoRKN.exe"));

        // First pass: check for strong root
        foreach (var c in candidates)
        {
            if (IsStrongRoot(c))
            {
                return c;
            }
        }

        // Second pass: check for acceptable root (app directory)
        foreach (var c in candidates)
        {
            if (IsAcceptableRoot(c))
            {
                return c;
            }
        }

        // Fallback: use app base directory if nothing else found
        var fallback = AppContext.BaseDirectory;
        if (Directory.Exists(fallback))
        {
            return fallback;
        }

        throw new DirectoryNotFoundException("Project root not found.");

    }

    private void StartProfile(string mode)
    {
        try
        {
            if (!_isAdmin)
            {
                var answer = MessageBox.Show(
                    "Start requires administrator rights. Restart GUI as administrator now?",
                    "NoRKN",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Question);

                if (answer == DialogResult.Yes)
                {
                    var args = Environment.GetCommandLineArgs().Skip(1).ToArray();
                    if (Program.TryRestartAsAdministrator(args))
                    {
                        Close();
                    }
                }

                return;
            }

            StopProfile(true);
            KillProc("winws2.exe");
            KillProc("winws.exe");
            PrepareWinDivertServices();

            var hostsAppend = BuildHostsAppend();
            var chatGptAppend = BuildChatGptAppend();
            var append = BuildAppend(mode);
            var presetParts = new List<string> { _basePresetPath };
            if (hostsAppend != null)
            {
                presetParts.Add(hostsAppend);
            }


            if (chatGptAppend != null)
            {
                presetParts.Add(chatGptAppend);
            }

            if (append != null)
            {
                presetParts.Add(append);
            }

            var presetArg = string.Join(";", presetParts);

            var psi = new ProcessStartInfo("powershell.exe")
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8,
                CreateNoWindow = _chkHidden.Checked,
                WindowStyle = _chkHidden.Checked ? ProcessWindowStyle.Hidden : ProcessWindowStyle.Normal,
                WorkingDirectory = _rootDir
            };
            psi.ArgumentList.Add("-NoProfile");
            psi.ArgumentList.Add("-ExecutionPolicy");
            psi.ArgumentList.Add("Bypass");
            psi.ArgumentList.Add("-File");
            psi.ArgumentList.Add(_runnerPath);
            psi.ArgumentList.Add("-EnginePath");
            psi.ArgumentList.Add(_enginePath);
            psi.ArgumentList.Add("-BaseDir");
            psi.ArgumentList.Add(_rootDir);
            psi.ArgumentList.Add("-PresetFile");
            psi.ArgumentList.Add(presetArg);

            _runnerProcess = new Process { StartInfo = psi, EnableRaisingEvents = true };
            _runnerProcess.OutputDataReceived += RunnerOut;
            _runnerProcess.ErrorDataReceived += RunnerOut;
            _runnerProcess.Exited += RunnerExit;

            if (!_runnerProcess.Start())
            {
                throw new InvalidOperationException("Runner process did not start.");
            }

            _runnerProcess.BeginOutputReadLine();
            _runnerProcess.BeginErrorReadLine();
            SetStatus("running", mode, _runnerProcess.Id);
            AppendLog($"[ui] started mode: {mode}");
        }
        catch (Exception ex)
        {
            AppendLog($"[error] {ex.Message}");
            SetStatus("error", "-", null);
        }
    }

    private void StopProfile(bool silent)
    {
        try
        {
            if (_runnerProcess is { HasExited: false })
            {
                _runnerProcess.Kill(true);
                _runnerProcess.WaitForExit(1500);
            }
        }
        catch
        {
        }

        try
        {
            _runnerProcess?.Dispose();
        }
        catch
        {
        }

        _runnerProcess = null;
        foreach (var f in _tempFiles.ToArray())
        {
            try
            {
                if (File.Exists(f))
                {
                    File.Delete(f);
                }
            }
            catch
            {
            }
        }
        _tempFiles.Clear();

        KillProc("winws2.exe");
        KillProc("winws.exe");
        SetStatus("stopped", "-", null);
        if (!silent)
        {
            AppendLog("[ui] stopped");
        }
    }

    private void PollRunner()
    {
        if (_runnerProcess == null)
        {
            return;
        }

        if (_runnerProcess.HasExited)
        {
            var code = _runnerProcess.ExitCode;
            _runnerProcess.Dispose();
            _runnerProcess = null;
            SetStatus("idle", "-", null);
            AppendLog($"[runner] exited code {code}");
            if (code == 34)
            {
                AppendLog("[hint] WinDivert не смог запуститься. Проверьте: запуск от администратора, наличие WinDivert64.sys рядом с winws2.exe, и что служба WinDivert не отключена.");
            }
            return;
        }

        _lblPid.Text = $"Runner PID: {_runnerProcess.Id}";
    }

    private void RunnerOut(object sender, DataReceivedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(e.Data))
        {
            AppendLog(e.Data);
        }
    }

    private void RunnerExit(object? sender, EventArgs e)
    {
        if (!IsHandleCreated || IsDisposed)
        {
            return;
        }

        try
        {
            BeginInvoke(new Action(() =>
            {
                if (_runnerProcess == null)
                {
                    return;
                }

                var code = _runnerProcess.ExitCode;
                _runnerProcess.Dispose();
                _runnerProcess = null;
                SetStatus("idle", "-", null);
                AppendLog($"[runner] exited code {code}");
                if (code == 34)
                {
                    AppendLog("[hint] WinDivert не смог запуститься. Проверьте: запуск от администратора, наличие WinDivert64.sys рядом с winws2.exe, и что служба WinDivert не отключена.");
                }
            }));
        }
        catch
        {
        }
    }

    private void SetStatus(string state, string mode, int? pid)
    {
        _runState = state;
        _runMode = mode;
        _lblStatus.Text = state switch
        {
            "running" => "Запущен",
            "error" => "Ошибка",
            "stopped" => "Остановлен",
            _ => "Ожидание"
        };
        _lblStatusHint.Text = state switch
        {
            "running" => "Обход блокировок активен",
            "error" => "Проверьте логи ниже",
            "stopped" => "Профиль остановлен",
            _ => "Ожидает запуска"
        };
        _lblRunSummary.Text = state switch
        {
            "running" => "DPI успешно запущен",
            "error" => "Ошибка запуска DPI",
            "stopped" => "DPI остановлен",
            _ => "DPI не запущен"
        };
        _lblMode.Text = $"Режим: {mode}";
        _lblPid.Text = pid.HasValue ? $"Runner PID: {pid.Value}" : "Runner PID: -";
        UpdateStatusColor();
    }

    private void UpdateStatusColor()
    {
        var statusColor = _runState switch
        {
            "running" => Color.FromArgb(112, 218, 142),
            "error" => Color.FromArgb(232, 95, 95),
            _ => Color.FromArgb(160, 160, 160)
        };
        _statusDot.BackColor = statusColor;
        _lblStatus.ForeColor = statusColor;
    }

    private void AppendLog(string text)
    {
        if (IsDisposed)
        {
            return;
        }

        if (InvokeRequired)
        {
            BeginInvoke(new Action<string>(AppendLog), text);
            return;
        }

        var logLine = $"[{DateTime.Now:HH:mm:ss}] {text}{Environment.NewLine}";
        
        if (_logBox != null && !_logBox.IsDisposed)
        {
            _logBox.AppendText(logLine);
            _logBox.SelectionStart = _logBox.TextLength;
            _logBox.ScrollToCaret();
        }
        
        if (_miniLogBox != null && !_miniLogBox.IsDisposed && !ReferenceEquals(_miniLogBox, _logBox))
        {
            _miniLogBox.AppendText(logLine);
            _miniLogBox.SelectionStart = _miniLogBox.TextLength;
            _miniLogBox.ScrollToCaret();
        }
    }

    private string? BuildAppend(string mode)
    {
        if (!_chkSupplement.Checked)
        {
            return null;
        }

        var host = FirstExisting(
            Path.Combine(_rootDir, "lists", "list-roblox.txt"),
            Path.Combine(_rootDir, "list-roblox.txt"),
            Path.Combine(_rootDir, "lists", "roblox_domains.txt"),
            Path.Combine(_rootDir, "roblox_domains.txt"));

        var ipset = FirstExisting(
            Path.Combine(_rootDir, "lists", "ipset-roblox.txt"),
            Path.Combine(_rootDir, "ipset-roblox.txt"),
            Path.Combine(_rootDir, "lists", "roblox_ips.txt"),
            Path.Combine(_rootDir, "roblox_ips.txt"));

        if (_chkAutoLists.Checked)
        {
            var auto = BuildAutoLists();
            host = auto.host ?? host;
            ipset = auto.ip ?? ipset;
            AppendLog($"[lists] auto host files={auto.hostCount}, ipset files={auto.ipCount}");
        }

        if (host == null || ipset == null)
        {
            AppendLog("[lists] supplement skipped (missing host/ipset)");
            return null;
        }

        host = ToRunnerPath(host);
        ipset = ToRunnerPath(ipset);

        var temp = Path.Combine(Path.GetTempPath(), $"zapret_gui_{mode}_{Guid.NewGuid():N}.args");
        var lines = new List<string>();
        if (mode == "multisplit")
        {
            lines.Add("--new");
            lines.Add("--filter-udp=49152-65535");
            lines.Add($"--hostlist={host}");
            lines.Add($"--ipset={ipset}");
            lines.Add("--out-range=-d8");
            lines.Add("--payload=all");
            lines.Add("--lua-desync=fake:blob=quic_google:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=10");
        }
        else
        {
            lines.Add("--new");
            lines.Add("--filter-udp=49152-65535");
            lines.Add($"--hostlist={host}");
            lines.Add($"--ipset={ipset}");
            lines.Add("--out-range=-d10");
            lines.Add("--payload=all");
            lines.Add("--lua-desync=fake:blob=quic_google:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=12");
        }
        File.WriteAllLines(temp, lines, new UTF8Encoding(true));
        _tempFiles.Add(temp);
        return temp;
    }
    private string? BuildHostsAppend()
    {
        var candidates = new[]
        {
            Path.Combine(_rootDir, "lists", "hosts.txt"),
            Path.Combine(_rootDir, "hosts.txt"),
            @"D:\hosts.txt"
        };

        var sourceFiles = candidates
            .Where(File.Exists)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (sourceFiles.Length == 0)
        {
            return null;
        }

        var hostSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var ipSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var file in sourceFiles)
        {
            foreach (var line in File.ReadLines(file))
            {
                if (!TryParseHostsLine(line, out var ip, out var hosts))
                {
                    continue;
                }

                ipSet.Add(ip);
                foreach (var hostName in hosts)
                {
                    hostSet.Add(hostName);
                }
            }
        }

        if (hostSet.Count == 0)
        {
            AppendLog("[lists] hosts append skipped (no valid host mappings)");
            return null;
        }

        var hostFile = Path.Combine(Path.GetTempPath(), $"zapret_gui_hosts_{Guid.NewGuid():N}.txt");
        var ipFile = Path.Combine(Path.GetTempPath(), $"zapret_gui_hosts_ipset_{Guid.NewGuid():N}.txt");

        File.WriteAllLines(hostFile, hostSet.OrderBy(x => x, StringComparer.OrdinalIgnoreCase), new UTF8Encoding(true));
        File.WriteAllLines(ipFile, ipSet.OrderBy(x => x, StringComparer.OrdinalIgnoreCase), new UTF8Encoding(true));
        _tempFiles.Add(hostFile);
        _tempFiles.Add(ipFile);

        var host = ToRunnerPath(hostFile);
        var ipset = ToRunnerPath(ipFile);
        var temp = Path.Combine(Path.GetTempPath(), $"zapret_gui_hosts_append_{Guid.NewGuid():N}.args");
        var lines = new List<string>
        {
            "--new",
            "--filter-tcp=80,443-65535",
            $"--hostlist={host}",
            "--out-range=-d8",
            "--lua-desync=send:repeats=2",
            "--lua-desync=tls_multisplit_sni:seqovl=652:seqovl_pattern=tls_google",
            "--new",
            "--filter-udp=80,443-65535",
            $"--hostlist={host}",
            $"--ipset={ipset}",
            "--out-range=-d8",
            "--payload=all",
            "--lua-desync=fake:blob=quic_google:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=10"
        };

        File.WriteAllLines(temp, lines, new UTF8Encoding(true));
        _tempFiles.Add(temp);
        AppendLog($"[lists] hosts profile enabled: hosts={hostSet.Count}, ips={ipSet.Count}");
        return temp;
    }

    private static bool TryParseHostsLine(string line, out string ip, out List<string> hosts)
    {
        ip = string.Empty;
        hosts = new List<string>();

        if (string.IsNullOrWhiteSpace(line))
        {
            return false;
        }

        var raw = line.Trim();
        if (raw.StartsWith("#"))
        {
            return false;
        }

        var commentIndex = raw.IndexOf('#');
        if (commentIndex >= 0)
        {
            raw = raw[..commentIndex].Trim();
        }

        if (raw.Length == 0)
        {
            return false;
        }

        var tokens = raw.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
        if (tokens.Length < 2)
        {
            return false;
        }

        if (!IPAddress.TryParse(tokens[0], out var parsedIp))
        {
            return false;
        }

        ip = parsedIp.ToString();

        for (var i = 1; i < tokens.Length; i++)
        {
            var host = tokens[i].Trim().TrimEnd('.');
            if (!LooksLikeHost(host))
            {
                continue;
            }

            hosts.Add(host.ToLowerInvariant());
        }

        return hosts.Count > 0;
    }

    private static bool LooksLikeHost(string token)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            return false;
        }

        if (token.Equals("localhost", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (token.Length < 3 || token.Length > 253)
        {
            return false;
        }

        if (token.Any(char.IsWhiteSpace))
        {
            return false;
        }

        return token.Contains('.') && token.All(c => char.IsLetterOrDigit(c) || c is '-' or '.');
    }
    private string? BuildChatGptAppend()
    {
        var host = FirstExisting(
            Path.Combine(_rootDir, "lists", "neural_domains.txt"),
            Path.Combine(_rootDir, "neural_domains.txt"));

        var ipset = FirstExisting(
            Path.Combine(_rootDir, "lists", "ipset-openai.txt"),
            Path.Combine(_rootDir, "ipset-openai.txt"),
            Path.Combine(_rootDir, "lists", "ipset-dns.txt"),
            Path.Combine(_rootDir, "ipset-dns.txt"));

        if (host == null || ipset == null)
        {
            AppendLog("[lists] chatgpt append skipped (missing neural_domains/ipset-openai)");
            return null;
        }

        host = ToRunnerPath(host);
        ipset = ToRunnerPath(ipset);

        var temp = Path.Combine(Path.GetTempPath(), $"zapret_gui_chatgpt_{Guid.NewGuid():N}.args");
        var lines = new List<string>
        {
            "--new",
            "--filter-tcp=443",
            $"--hostlist={host}",
            "--out-range=-d8",
            "--lua-desync=send:repeats=2",
            "--lua-desync=tls_multisplit_sni:seqovl=652:seqovl_pattern=tls_google",
            "--new",
            "--filter-udp=443",
            $"--hostlist={host}",
            $"--ipset={ipset}",
            "--out-range=-d8",
            "--payload=all",
            "--lua-desync=fake:blob=quic_google:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=10"
        };

        File.WriteAllLines(temp, lines, new UTF8Encoding(true));
        _tempFiles.Add(temp);
        AppendLog($"[lists] chatgpt profile enabled: host={host}, ipset={ipset}");
        return temp;
    }

    private string ToRunnerPath(string path)
    {
        try
        {
            var full = Path.GetFullPath(path);
            var root = Path.GetFullPath(_rootDir);
            if (full.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            {
                var rel = Path.GetRelativePath(root, full);
                return rel.Replace('\\', '/');
            }
        }
        catch
        {
            // ignore and fallback to absolute path
        }
        return path;
    }

    private (string? host, string? ip, int hostCount, int ipCount) BuildAutoLists()
    {
        var listsDir = Path.Combine(_rootDir, "lists");
        Directory.CreateDirectory(listsDir);
        var hostFile = Path.Combine(listsDir, "_auto_hostlist.txt");
        var ipFile = Path.Combine(listsDir, "_auto_ipset.txt");
        File.WriteAllText(hostFile, "");
        File.WriteAllText(ipFile, "");

        var hostCount = 0;
        var ipCount = 0;
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var dir in new[] { listsDir, _rootDir })
        {
            if (!Directory.Exists(dir))
            {
                continue;
            }

            foreach (var file in Directory.GetFiles(dir, "*.txt", SearchOption.TopDirectoryOnly))
            {
                var name = Path.GetFileName(file);
                if (!seen.Add(name) || name.EndsWith(".Zone.Identifier", StringComparison.OrdinalIgnoreCase) ||
                    name.Equals("_auto_hostlist.txt", StringComparison.OrdinalIgnoreCase) ||
                    name.Equals("_auto_ipset.txt", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var isIp = Path.GetFileNameWithoutExtension(file).Contains("ipset", StringComparison.OrdinalIgnoreCase) ||
                           Path.GetFileNameWithoutExtension(file).Contains("_ips", StringComparison.OrdinalIgnoreCase);
                var target = isIp ? ipFile : hostFile;
                File.AppendAllText(target, File.ReadAllText(file, Encoding.UTF8) + Environment.NewLine, Encoding.UTF8);
                if (isIp) ipCount++; else hostCount++;
            }
        }

        string? host = new FileInfo(hostFile).Length > 0 ? hostFile : null;
        string? ip = new FileInfo(ipFile).Length > 0 ? ipFile : null;
        return (host, ip, hostCount, ipCount);
    }

    private static string? FirstExisting(params string[] paths)
    {
        foreach (var p in paths)
        {
            if (File.Exists(p))
            {
                return p;
            }
        }
        return null;
    }

    private static void KillProc(string image)
    {
        try
        {
            using var p = Process.Start(new ProcessStartInfo
            {
                FileName = "taskkill",
                Arguments = $"/F /IM {image}",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            });
            p?.WaitForExit(1000);
        }
        catch
        {
        }
    }

    private void PrepareWinDivertServices()
    {
        if (!_isAdmin)
        {
            return;
        }

        try
        {
            var sysPath = Path.Combine(_rootDir, "WinDivert64.sys");
            if (!File.Exists(sysPath))
            {
                AppendLog($"[windivert] missing driver file: {sysPath}");
                return;
            }

            var candidates = new[] { "WinDivert", "WinDivert14", "WinDivert1.4" };
            var anyReady = false;

            foreach (var service in candidates)
            {
                var (qCode, qOut, qErr) = RunProcessCapture(
                    "sc.exe",
                    new[] { "query", service });
                var queryText = $"{qOut}\n{qErr}";
                var missing = qCode != 0 && queryText.Contains("1060", StringComparison.OrdinalIgnoreCase);

                if (missing)
                {
                    var (createCode, createOut, createErr) = RunProcessCapture(
                        "sc.exe",
                        new[]
                        {
                            "create", service,
                            "type=", "kernel",
                            "start=", "demand",
                            "error=", "normal",
                            "binPath=", sysPath
                        });
                    var createText = $"{createOut}\n{createErr}";
                    if (createCode == 0 || createText.Contains("1073", StringComparison.OrdinalIgnoreCase))
                    {
                        AppendLog($"[windivert] service '{service}' created");
                    }
                    else
                    {
                        AppendLog($"[windivert] create '{service}' failed ({createCode})");
                        continue;
                    }
                }

                var (cfgCode, cfgOut, cfgErr) = RunProcessCapture(
                    "sc.exe",
                    new[]
                    {
                        "config", service,
                        "type=", "kernel",
                        "start=", "demand",
                        "error=", "normal",
                        "binPath=", sysPath
                    });
                if (cfgCode != 0)
                {
                    AppendLog($"[windivert] config '{service}' failed ({cfgCode})");
                    var cfgText = $"{cfgOut}\n{cfgErr}".Trim();
                    if (!string.IsNullOrWhiteSpace(cfgText))
                    {
                        AppendLog($"[windivert] {cfgText}");
                    }
                    continue;
                }

                var (startCode, startOut, startErr) = RunProcessCapture(
                    "sc.exe",
                    new[] { "start", service });
                var startText = $"{startOut}\n{startErr}";
                if (startCode == 0 || startText.Contains("1056", StringComparison.OrdinalIgnoreCase))
                {
                    AppendLog($"[windivert] service '{service}' ready");
                    anyReady = true;
                    break;
                }

                AppendLog($"[windivert] start '{service}' failed ({startCode})");
                if (startText.Contains("577", StringComparison.OrdinalIgnoreCase))
                {
                    AppendLog("[windivert] код 577: драйвер заблокирован проверкой подписи/безопасностью Windows.");
                }
                else if (startText.Contains("1058", StringComparison.OrdinalIgnoreCase))
                {
                    AppendLog("[windivert] код 1058: служба отключена политикой или системой.");
                }
                else if (startText.Contains("no enabled devices associated with it", StringComparison.OrdinalIgnoreCase))
                {
                    AppendLog("[windivert] у драйвера нет активного устройства. Проверьте совместимость драйвера WinDivert с вашей системой.");
                }
            }

            if (!anyReady)
            {
                AppendLog("[windivert] auto-fix did not start driver service");
            }
        }
        catch (Exception ex)
        {
            AppendLog($"[windivert] prepare failed: {ex.Message}");
        }
    }

    private async void RunDiag()
    {
        _btnDiag.Enabled = false;
        try
        {
            var path = Path.Combine(_rootDir, "check_roblox_mode.bat");
            if (!File.Exists(path))
            {
                AppendLog("[diag] check_roblox_mode.bat not found");
                return;
            }

            AppendLog("[diag] started");

            var psi = new ProcessStartInfo("cmd.exe", $"/c \"{path}\"")
            {
                WorkingDirectory = _rootDir,
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using var p = Process.Start(psi);
            if (p != null)
            {
                var outputTask = p.StandardOutput.ReadToEndAsync();
                var errorTask = p.StandardError.ReadToEndAsync();
                var waitTask = p.WaitForExitAsync();
                var completed = await Task.WhenAny(waitTask, Task.Delay(TimeSpan.FromSeconds(90)));

                if (completed != waitTask)
                {
                    try
                    {
                        if (!p.HasExited)
                        {
                            p.Kill(true);
                        }
                    }
                    catch
                    {
                        // ignore
                    }

                    AppendLog("[diag] timeout (90s), process terminated");
                    return;
                }

                var output = await outputTask;
                var error = await errorTask;
                if (!string.IsNullOrWhiteSpace(output))
                {
                    AppendLog(output);
                }
                if (!string.IsNullOrWhiteSpace(error))
                {
                    AppendLog($"[error] {error}");
                }
            }
            AppendLog("[diag] completed");
        }
        catch (Exception ex)
        {
            AppendLog($"[diag] error: {ex.Message}");
        }
        finally
        {
            _btnDiag.Enabled = true;
        }
    }

    private void OpenFolder()
    {
        if (Directory.Exists(_rootDir))
        {
            Process.Start("explorer.exe", _rootDir);
        }
    }

    private void OpenPreset()
    {
        if (File.Exists(_basePresetPath))
        {
            Process.Start("notepad.exe", _basePresetPath);
        }
    }

    private void OpenLists()
    {
        var path = Path.Combine(_rootDir, "lists");
        if (Directory.Exists(path))
        {
            Process.Start("explorer.exe", path);
        }
    }

    private void InstallServiceAutostart()
    {
        if (!EnsureAdminForAction("Установка службы автозапуска"))
        {
            return;
        }

        try
        {
            if (string.IsNullOrWhiteSpace(_rootDir))
            {
                AppendLog("[service] root not ready yet");
                return;
            }

            // Get the mode setting
            var mode = GetCurrentMode();
            if (string.IsNullOrWhiteSpace(mode))
            {
                mode = "multisplit";
            }

            AppendLog("[service] installing Windows service...");

            var (success, message) = ServiceInstaller.InstallService(_rootDir, mode);

            if (!success)
            {
                throw new InvalidOperationException(message);
            }

            AppendLog($"[service] {message}");
            RefreshServiceState();

            MessageBox.Show(message, "Служба установлена", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            AppendLog($"[service] install error: {ex.Message}");
            MessageBox.Show(ex.Message, "Ошибка установки", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void RemoveServiceAutostart()
    {
        if (!EnsureAdminForAction("Удаление службы"))
        {
            return;
        }

        try
        {
            AppendLog("[service] removing Windows service...");

            var (success, message) = ServiceInstaller.RemoveService();

            if (!success)
            {
                throw new InvalidOperationException(message);
            }

            AppendLog($"[service] {message}");
            RefreshServiceState();

            MessageBox.Show(message, "Служба удалена", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            AppendLog($"[service] remove error: {ex.Message}");
            MessageBox.Show(ex.Message, "Ошибка удаления", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void RefreshServiceState()
    {
        if (_lblServiceState == null || _lblServiceState.IsDisposed)
        {
            return;
        }

        if (string.IsNullOrWhiteSpace(_rootDir))
        {
            _lblServiceState.Text = "Состояние: ожидание инициализации";
            return;
        }

        var installed = ServiceInstaller.ServiceExists();
        var status = installed ? ServiceInstaller.GetServiceStatus() : "Not installed";
        
        _lblServiceState.Text = installed
            ? $"Состояние: установлено ({status}) (включается при старте системы)"
            : "Состояние: не установлено";
    }

    private string GetCurrentMode()
    {
        // Return the last selected/running mode
        if (!string.IsNullOrWhiteSpace(_runMode) && _runMode != "-")
        {
            return _runMode;
        }
        
        // Default to multisplit if no mode has been selected
        return "multisplit";
    }

    private (int ExitCode, string StdOut, string StdErr) RunProcessCapture(string fileName, IEnumerable<string> arguments)
    {
        using var p = new Process();
        p.StartInfo.FileName = fileName;
        p.StartInfo.UseShellExecute = false;
        p.StartInfo.CreateNoWindow = true;
        p.StartInfo.RedirectStandardOutput = true;
        p.StartInfo.RedirectStandardError = true;
        p.StartInfo.StandardOutputEncoding = Encoding.UTF8;
        p.StartInfo.StandardErrorEncoding = Encoding.UTF8;
        foreach (var arg in arguments)
        {
            p.StartInfo.ArgumentList.Add(arg);
        }

        p.Start();
        var stdout = p.StandardOutput.ReadToEnd();
        var stderr = p.StandardError.ReadToEnd();
        p.WaitForExit();
        return (p.ExitCode, stdout, stderr);
    }

    private bool EnsureAdminForAction(string actionTitle)
    {
        if (_isAdmin)
        {
            return true;
        }

        var answer = MessageBox.Show(
            $"{actionTitle} требует прав администратора. Перезапустить GUI с правами администратора?",
            "NoRKN",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question);

        if (answer == DialogResult.Yes)
        {
            var args = Environment.GetCommandLineArgs().Skip(1).ToArray();
            if (Program.TryRestartAsAdministrator(args))
            {
                Close();
            }
        }

        return false;
    }

    private void SaveLogs()
    {
        using var sfd = new SaveFileDialog
        {
            Filter = "Text (*.txt)|*.txt|All files (*.*)|*.*",
            FileName = $"norkn-log-{DateTime.Now:yyyyMMdd-HHmmss}.txt"
        };
        if (sfd.ShowDialog(this) == DialogResult.OK)
        {
            File.WriteAllText(sfd.FileName, _logBox.Text, Encoding.UTF8);
            AppendLog($"[ui] saved log: {sfd.FileName}");
        }
    }

    private void ToggleWindowState()
    {
        WindowState = WindowState == FormWindowState.Maximized
            ? FormWindowState.Normal
            : FormWindowState.Maximized;
    }

    private void SyncMaxButton()
    {
        if (_btnMax == null || _btnMax.IsDisposed)
        {
            return;
        }

        _btnMax.Text = WindowState == FormWindowState.Maximized ? "❐" : "□";
    }

    private void ApplyRoundMask()
    {
        if (WindowState == FormWindowState.Maximized)
        {
            Region = null;
            return;
        }

        using var path = RoundedPath(new Rectangle(0, 0, Width, Height), 18);
        Region = new Region(path);
    }

    private void TitleDrag_MouseDown(object? sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left)
        {
            return;
        }
        ReleaseCapture();
        SendMessage(Handle, 0xA1, 0x2, 0);
    }

    private static GraphicsPath RoundedPath(Rectangle r, int radius)
    {
        var d = radius * 2;
        var p = new GraphicsPath();
        var arc = new Rectangle(r.Left, r.Top, d, d);
        p.AddArc(arc, 180, 90);
        arc.X = r.Right - d; p.AddArc(arc, 270, 90);
        arc.Y = r.Bottom - d; p.AddArc(arc, 0, 90);
        arc.X = r.Left; p.AddArc(arc, 90, 90);
        p.CloseFigure();
        return p;
    }

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, int msg, int wParam, int lParam);

    private sealed class NorknLogoControl : Control
    {
        public NorknLogoControl()
        {
            SetStyle(
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.UserPaint |
                ControlStyles.ResizeRedraw |
                ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            var bounds = new Rectangle(0, 0, Width - 1, Height - 1);
            if (bounds.Width <= 1 || bounds.Height <= 1)
            {
                return;
            }

            using (var bgPath = RoundedPath(bounds, 6))
            using (var redBrush = new SolidBrush(Color.FromArgb(211, 47, 47)))
            {
                g.FillPath(redBrush, bgPath);
            }

            var circleRect = new RectangleF(2.5f, 2.5f, Width - 6f, Height - 6f);
            using (var whiteBrush = new SolidBrush(Color.White))
            {
                g.FillEllipse(whiteBrush, circleRect);
            }

            var iconRect = new RectangleF(3.5f, 3.5f, Width - 8f, Height - 8f);
            var sx = iconRect.Width / 1024f;
            var sy = iconRect.Height / 1024f;
            PointF P(float x, float y) => new(iconRect.Left + x * sx, iconRect.Top + y * sy);

            var p1 = new[]
            {
                P(765.748f, 167.568f),
                P(598.331f, 0.151f),
                P(425.5f, 0f),
                P(0f, 425.5f),
                P(0f, 598.5f),
                P(167.4f, 765.915f),
                P(295.753f, 637.563f),
                P(170.191f, 512f),
                P(512f, 170.191f),
                P(637.563f, 295.753f)
            };

            var p2 = new[]
            {
                P(512.9f, 339.5f),
                P(685.9f, 512.5f),
                P(512.5f, 685.9f),
                P(339.5f, 512.9f)
            };

            var p3 = new[]
            {
                P(258.252f, 856.432f),
                P(425.669f, 1023.85f),
                P(598.499f, 1024.02f),
                P(1024.02f, 598.5f),
                P(1024.02f, 425.5f),
                P(856.6f, 258.085f),
                P(728.247f, 386.437f),
                P(853.809f, 512f),
                P(512f, 853.809f),
                P(386.437f, 728.247f)
            };

            using var blackBrush = new SolidBrush(Color.Black);
            g.FillPolygon(blackBrush, p1);
            g.FillPolygon(blackBrush, p2);
            g.FillPolygon(blackBrush, p3);

            base.OnPaint(e);
        }
    }

    private sealed class GradientPanel : Panel
    {
        public bool DarkTheme { get; set; } = true;
        public bool RedTheme { get; set; }
        public bool GreenTheme { get; set; }

        public GradientPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            DoubleBuffered = true;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;

            var r = ClientRectangle;

            if (GreenTheme)
            {
                using var gradientBrush = new LinearGradientBrush(r,
                    Color.FromArgb(18, 70, 41),
                    Color.FromArgb(10, 34, 20),
                    45f);
                g.FillRectangle(gradientBrush, r);
            }
            else if (RedTheme)
            {
                using var gradientBrush = new LinearGradientBrush(r, 
                    Color.FromArgb(85, 18, 28), 
                    Color.FromArgb(45, 10, 16), 
                    45f);
                g.FillRectangle(gradientBrush, r);
            }
            else if (DarkTheme)
            {
                using var gradientBrush = new LinearGradientBrush(r,
                    Color.FromArgb(24, 29, 35),
                    Color.FromArgb(16, 20, 24),
                    45f);
                g.FillRectangle(gradientBrush, r);
            }
            else
            {
                // Light theme
                using var gradientBrush = new LinearGradientBrush(r,
                    Color.FromArgb(237, 245, 255),
                    Color.FromArgb(220, 235, 255),
                    45f);
                g.FillRectangle(gradientBrush, r);
            }

            base.OnPaint(e);
        }
    }

    private sealed class GlassPanel : Panel
    {
        public int Radius { get; set; } = 16;
        public Color FillColor { get; set; } = Color.FromArgb(26, 255, 255, 255);
        public Color BorderColor { get; set; } = Color.FromArgb(41, 255, 255, 255);

        public GlassPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            var rect = ClientRectangle;
            rect.Width -= 1;
            rect.Height -= 1;
            if (rect.Width < 2 || rect.Height < 2)
            {
                return;
            }

            using var path = RoundedPath(rect, Radius);
            using var fill = new SolidBrush(FillColor);
            using var border = new Pen(BorderColor, 1);
            g.FillPath(fill, path);
            g.DrawPath(border, path);

            base.OnPaint(e);
        }
    }
}







