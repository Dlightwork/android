namespace ZapretGlassGui;

partial class Form1
{
    /// <summary>
    ///  Required designer variable.
    /// </summary>
    private System.ComponentModel.IContainer components = null!;

    /// <summary>
    ///  Clean up any resources being used.
    /// </summary>
    /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
    protected override void Dispose(bool disposing)
    {
        if (disposing && (components != null))
        {
            components.Dispose();
        }

        base.Dispose(disposing);
    }

    #region Windows Form Designer generated code

    /// <summary>
    ///  Required method for Designer support - do not modify
    ///  the contents of this method with the code editor.
    /// </summary>
    private void InitializeComponent()
    {
        components = new System.ComponentModel.Container();
        AutoScaleMode = AutoScaleMode.Font;
        BackColor = Color.FromArgb(16, 20, 24);
        ClientSize = new Size(1180, 760);
        DoubleBuffered = true;
        Font = new Font("Segoe UI", 9F, FontStyle.Regular, GraphicsUnit.Point);
        FormBorderStyle = FormBorderStyle.None;
        MinimumSize = new Size(1020, 640);
        Name = "Form1";
        StartPosition = FormStartPosition.CenterScreen;
        Text = "NoRKN";
        WindowState = FormWindowState.Maximized;
        Visible = false;  // Скрыть окно при создании (покажется в OnShown)
    }

    #endregion
}
