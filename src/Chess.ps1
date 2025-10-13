# PowerShell Chess (WinForms + UTF-8) - Drag to move, double-buffered
# PowerShell 5.1 / older C# compilers compatible (no tuples/interpolated strings/expr-bodied members)

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;

namespace TinyCsChess
{
    public class Move
    {
        public int From;
        public int To;
        public char Promote; // '\0' if none
        public Move(int from, int to, char promote) { From = from; To = to; Promote = promote; }
    }

    public class Board
    {
        public char[] S = new char[64]; // model index: rank*8+file, rank 0 = white home rank
        public bool WhiteToMove = true;
        public int Half; public int Full;
        public Board(){ Reset(); }

        public void Reset()
        {
            string start =
                "RNBQKBNR" +
                "PPPPPPPP" +
                "........" +
                "........" +
                "........" +
                "........" +
                "pppppppp" +
                "rnbqkbnr";
            for(int i=0;i<64;i++) S[i]=start[i];
            WhiteToMove = true; Half=0; Full=1;
        }

        public Board Copy()
        {
            Board b = new Board();
            Array.Copy(S, b.S, 64);
            b.WhiteToMove = WhiteToMove;
            b.Half = Half; b.Full = Full;
            return b;
        }

        public static bool IsWhite(char p){ return p>='A' && p<='Z'; }
        public static bool IsBlack(char p){ return p>='a' && p<='z'; }
        public static int FileOf(int sq){ return sq%8; }
        public static int RankOf(int sq){ return sq/8; }

        public void MakeMove(Move m)
        {
            char piece = S[m.From];
            char captured = S[m.To];
            S[m.To] = piece;
            S[m.From] = '.';

            // auto-queen (correct sides)
            if(m.Promote!='\0') S[m.To]=m.Promote;
            else if(char.ToLower(piece)=='p'){
                int r = RankOf(m.To);
                if(r==7 && piece=='P') S[m.To]='Q'; // White reaches rank 7
                if(r==0 && piece=='p') S[m.To]='q'; // Black reaches rank 0
            }

            if(char.ToLower(piece)=='p' || captured!='.') Half=0; else Half++;
            if(!WhiteToMove) Full++;
            WhiteToMove = !WhiteToMove;
        }

        public List<Move> GetLegalMoves()
        {
            List<Move> ps = GetPseudo();
            List<Move> legal = new List<Move>();
            for(int i=0;i<ps.Count;i++){
                Move m = ps[i];
                Board c = Copy(); c.MakeMove(m);
                // Check the mover's king after the move
                if(!c.IsInCheck(!c.WhiteToMove)) legal.Add(m);
            }
            return legal;
        }

        private List<Move> GetPseudo()
        {
            List<Move> mv = new List<Move>();
            for(int sq=0; sq<64; sq++){
                char p=S[sq]; if(p=='.') continue;
                bool side = IsWhite(p);
                if(side!=WhiteToMove) continue;
                int f=FileOf(sq), r=RankOf(sq);
                char pl = char.ToLower(p);
                if(pl=='p'){
                    bool w = IsWhite(p);
                    int dir = w? +1 : -1;         // white forward increases rank
                    int startRank = w? 1 : 6;
                    int promoteRank = w? 7 : 0;

                    int fwd = sq + dir*8;
                    if(fwd>=0 && fwd<64 && S[fwd]=='.'){
                        if(RankOf(fwd)==promoteRank) mv.Add(new Move(sq,fwd, w?'Q':'q')); else mv.Add(new Move(sq,fwd,'\0'));
                        int dbl = sq + dir*16;
                        if(r==startRank && S[dbl]=='.') mv.Add(new Move(sq,dbl,'\0'));
                    }
                    int[] cdirs = new int[]{ dir*8-1, dir*8+1 };
                    for(int k=0;k<2;k++){
                        int to=sq+cdirs[k];
                        if(to>=0 && to<64){
                            int tf=FileOf(to);
                            if(Math.Abs(tf-f)==1 && S[to]!='.' && IsWhite(S[to])!=w){
                                if(RankOf(to)==promoteRank) mv.Add(new Move(sq,to, w?'Q':'q')); else mv.Add(new Move(sq,to,'\0'));
                            }
                        }
                    }
                }
                else if(pl=='n'){
                    int[] offs = new int[]{-17,-15,-10,-6,6,10,15,17};
                    for(int k=0;k<8;k++){
                        int to=sq+offs[k];
                        if(to>=0 && to<64){
                            int tf=FileOf(to), tr=RankOf(to);
                            if(Math.Abs(tf-f)<=2 && Math.Abs(tr-r)<=2){
                                char t=S[to];
                                if(t=='.' || IsWhite(t)!=IsWhite(p)) mv.Add(new Move(sq,to,'\0'));
                            }
                        }
                    }
                }
                else{
                    int[][] dirs;
                    if(pl=='b') dirs=new int[][]{new int[]{1,1},new int[]{1,-1},new int[]{-1,1},new int[]{-1,-1}};
                    else if(pl=='r') dirs=new int[][]{new int[]{1,0},new int[]{-1,0},new int[]{0,1},new int[]{0,-1}};
                    else if(pl=='q') dirs=new int[][]{new int[]{1,1},new int[]{1,-1},new int[]{-1,1},new int[]{-1,-1},new int[]{1,0},new int[]{-1,0},new int[]{0,1},new int[]{0,-1}};
                    else if(pl=='k') dirs=new int[][]{new int[]{1,1},new int[]{1,0},new int[]{1,-1},new int[]{0,1},new int[]{0,-1},new int[]{-1,1},new int[]{-1,0},new int[]{-1,-1}};
                    else dirs=null;

                    if(dirs!=null){
                        for(int d=0; d<dirs.Length; d++){
                            int df=dirs[d][0], dr=dirs[d][1];
                            int max = (pl=='k')?1:7;
                            for(int step=1; step<=max; step++){
                                int nf=f+df*step, nr=r+dr*step;
                                if(nf<0||nf>7||nr<0||nr>7) break;
                                int to=nr*8+nf; char t=S[to];
                                if(t=='.'){ mv.Add(new Move(sq,to,'\0')); }
                                else { if(IsWhite(t)!=IsWhite(p)) mv.Add(new Move(sq,to,'\0')); break; }
                            }
                        }
                    }
                }
            }
            return mv;
        }

        public bool IsInCheck(bool whiteKing)
        {
            int ksq=-1; char k = whiteKing? 'K':'k';
            for(int i=0;i<64;i++) if(S[i]==k){ ksq=i; break; }
            if(ksq<0) return false;
            for(int sq=0;sq<64;sq++){
                char p=S[sq]; if(p=='.' || IsWhite(p)==whiteKing) continue;
                if(CanAttack(sq, ksq)) return true;
            }
            return false;
        }

        private bool CanAttack(int from, int to)
        {
            char p = S[from]; char pl = char.ToLower(p);
            int ff=FileOf(from), fr=RankOf(from), tf=FileOf(to), tr=RankOf(to);
            int df=tf-ff, dr=tr-fr;

            if(pl=='p'){
                bool w = IsWhite(p);
                return (w && dr==1 && Math.Abs(df)==1) || (!w && dr==-1 && Math.Abs(df)==1);
            }
            if(pl=='n'){ return (Math.Abs(df)==2 && Math.Abs(dr)==1) || (Math.Abs(df)==1 && Math.Abs(dr)==2); }
            if(pl=='k'){ return Math.Abs(df)<=1 && Math.Abs(dr)<=1; }

            bool diag = Math.Abs(df)==Math.Abs(dr);
            bool ortho = (df==0 || dr==0);
            if(pl=='b' && !diag) return false;
            if(pl=='r' && !ortho) return false;
            if(pl=='q' && !(diag||ortho)) return false;

            int sxf = (df==0)?0:(df/Math.Abs(df));
            int sxr = (dr==0)?0:(dr/Math.Abs(dr));
            int steps = Math.Max(Math.Abs(df),Math.Abs(dr));
            for(int i=1;i<steps;i++){ int sq = (fr+i*sxr)*8 + (ff+i*sxf); if(S[sq] != '.') return false; }
            return true;
        }

        public int Evaluate()
        {
            int score=0;
            for(int i=0;i<64;i++){
                char p=S[i]; if(p=='.') continue;
                int val=0; switch(char.ToLower(p)){
                    case 'p': val=100; break; case 'n': val=320; break; case 'b': val=330; break;
                    case 'r': val=500; break; case 'q': val=900; break; case 'k': val=20000; break;
                }
                if(IsWhite(p)) score+=val; else score-=val;
            }
            return score;
        }
    }

    public class Engine
    {
        public int MaxDepth = 2; // keep snappy for drag UI

        public Move GetBestMove(Board b)
        {
            List<Move> moves = b.GetLegalMoves();
            if(moves.Count==0) return new Move(-1,-1,'\0');
            int best=-999999; Move bm=moves[0];
            for(int i=0;i<moves.Count;i++){
                Board c=b.Copy(); c.MakeMove(moves[i]);
                int sc = -AlphaBeta(c, MaxDepth-1, -999999, 999999);
                if(sc>best){ best=sc; bm=moves[i]; }
            }
            return bm;
        }

        private int AlphaBeta(Board b, int depth, int alpha, int beta)
        {
            if(depth<=0) return b.Evaluate() * (b.WhiteToMove?1:-1);
            List<Move> moves = b.GetLegalMoves();
            if(moves.Count==0) return b.IsInCheck(b.WhiteToMove)? -20000 : 0;
            for(int i=0;i<moves.Count;i++){
                Board c=b.Copy(); c.MakeMove(moves[i]);
                int sc = -AlphaBeta(c, depth-1, -beta, -alpha);
                if(sc>=beta) return beta;
                if(sc>alpha) alpha=sc;
            }
            return alpha;
        }
    }
}
"@ -ReferencedAssemblies System.Windows.Forms,System.Drawing

# Double-buffered Panel to kill flicker
Add-Type -TypeDefinition @"
using System.Windows.Forms;
using System.Drawing;

public class DbPanel : Panel
{
    public DbPanel()
    {
        this.DoubleBuffered = true;
        this.ResizeRedraw = true;
        this.SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
        this.UpdateStyles();
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        // Suppress default background erase to avoid flicker; we paint full board ourselves in OnPaint
        // base.OnPaintBackground(e);
    }
}
"@ -ReferencedAssemblies System.Windows.Forms

# --- WinForms UI (drag-to-move, double-buffered) ---

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$board  = New-Object TinyCsChess.Board
$engine = New-Object TinyCsChess.Engine
$engine.MaxDepth = 2

$tile = 72
$form = New-Object Windows.Forms.Form
$form.Text = "PowerShell Chess - Drag to Move"
$form.StartPosition = "CenterScreen"
$form.ClientSize = New-Object Drawing.Size -ArgumentList (8*$tile), (8*$tile + 56)
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.KeyPreview = $true

# Controls
$lblSide = New-Object Windows.Forms.Label
$lblSide.Text = "Play as:"
$lblSide.AutoSize = $true
$lblSide.Location = New-Object Drawing.Point -ArgumentList 8, 8

$sideCombo = New-Object Windows.Forms.ComboBox
$sideCombo.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
[void]$sideCombo.Items.Add("White")
[void]$sideCombo.Items.Add("Black")
$sideCombo.SelectedIndex = 0
$sideCombo.Location = New-Object Drawing.Point -ArgumentList 68, 4
$sideCombo.Width = 90

$btnNew = New-Object Windows.Forms.Button
$btnNew.Text = "New Game"
$btnNew.Location = New-Object Drawing.Point -ArgumentList 170, 3
$btnNew.Width = 90

$lblStatus = New-Object Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object Drawing.Point -ArgumentList 270, 8

# Use our flicker-free panel
$panel = New-Object DbPanel
$panel.Location = New-Object Drawing.Point -ArgumentList 0, 32
$panel.Size = New-Object Drawing.Size -ArgumentList (8*$tile), (8*$tile)
$panel.BackColor = [Drawing.Color]::FromArgb(230,230,230)
$panel.Cursor = [Windows.Forms.Cursors]::Hand

$form.Controls.AddRange(@($lblSide,$sideCombo,$btnNew,$lblStatus,$panel))

# Orientation
$script:HumanIsWhite = $true

# Drag state
$script:Dragging   = $false
$script:DragFrom   = -1
$script:DragPiece  = [char]0
$script:DragPoint  = New-Object Drawing.Point -ArgumentList 0, 0
$script:LegalTos   = @()

# ===== Sprite support (Wikipedia) — crisp, pre-sized to $tile =====
$script:SpritesOk   = $false
$script:SpriteSheet = $null
$script:PieceBmp    = @{}  # char -> System.Drawing.Bitmap ($tile x $tile)

function Initialize-Sprites {
    param([int]$TileSize)

    $desiredWidth = [Math]::Max(6*[int]$TileSize, 270)  # never smaller than 270
    $url = "https://commons.wikimedia.org/wiki/Special:FilePath/Chess_Pieces_Sprite.svg?width=$desiredWidth"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $wc = New-Object Net.WebClient
        $wc.Headers['User-Agent'] = 'PowerShellChess/1.0'
        $bytes = $wc.DownloadData($url)
        $wc.Dispose()

        if(-not $bytes -or $bytes.Length -lt 4096){ throw "Download failed or too small." }

        $ms  = New-Object IO.MemoryStream(,$bytes)
        $bmp = [Drawing.Bitmap]::FromStream($ms)
        $script:SpriteSheet = $bmp

        $cw = [int]([double]$bmp.Width / 6.0)
        $ch = [int]([double]$bmp.Height / 2.0)

        $cols = 'K','Q','B','N','R','P'
        $rows = 0,1

        foreach($r in $rows){
            foreach($i in 0..5){
                $srcRect = New-Object Drawing.Rectangle ($i*$cw), ($r*$ch), $cw, $ch

                $crop = New-Object Drawing.Bitmap $cw, $ch
                $g1 = [Drawing.Graphics]::FromImage($crop)
                $g1.CompositingQuality = 'HighQuality'
                $g1.InterpolationMode  = 'HighQualityBicubic'
                $g1.PixelOffsetMode    = 'HighQuality'
                $g1.SmoothingMode      = 'HighQuality'
                $g1.DrawImage($bmp, (New-Object Drawing.Rectangle 0,0,$cw,$ch), $srcRect, [Drawing.GraphicsUnit]::Pixel)
                $g1.Dispose()

                $scaled = New-Object Drawing.Bitmap $TileSize, $TileSize
                $g2 = [Drawing.Graphics]::FromImage($scaled)
                $g2.CompositingQuality = 'HighQuality'
                $g2.InterpolationMode  = 'HighQualityBicubic'
                $g2.PixelOffsetMode    = 'HighQuality'
                $g2.SmoothingMode      = 'HighQuality'
                $g2.DrawImage($crop, (New-Object Drawing.Rectangle 0,0,$TileSize,$TileSize), (New-Object Drawing.Rectangle 0,0,$cw,$ch), [Drawing.GraphicsUnit]::Pixel)
                $g2.Dispose()
                $crop.Dispose()

                $pieceChar = if($r -eq 0){ $cols[$i] } else { $cols[$i].ToLower() }
                $script:PieceBmp[[char]$pieceChar] = $scaled
            }
        }

        $script:PieceBmp[[char]'.'] = $null
        $script:SpritesOk = $true
    }
    catch {
        $script:SpritesOk = $false
        if($script:SpriteSheet){ $script:SpriteSheet.Dispose(); $script:SpriteSheet = $null }
        # fallback handled in DrawPiece
    }
}


# Glyphs / reusable resources (fallback mode)
$glyph = @{
    ([char]'K') = ([string][char]0x2654)
    ([char]'Q') = ([string][char]0x2655)
    ([char]'R') = ([string][char]0x2656)
    ([char]'B') = ([string][char]0x2657)
    ([char]'N') = ([string][char]0x2658)
    ([char]'P') = ([string][char]0x2659)
    ([char]'k') = ([string][char]0x265A)
    ([char]'q') = ([string][char]0x265B)
    ([char]'r') = ([string][char]0x265C)
    ([char]'b') = ([string][char]0x265D)
    ([char]'n') = ([string][char]0x265E)
    ([char]'p') = ([string][char]0x265F)
    ([char]'.') = ""
}
$font      = New-Object Drawing.Font -ArgumentList 'Segoe UI Symbol', ([single]46), ([Drawing.FontStyle]::Regular)
$sf        = New-Object Drawing.StringFormat
$sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
$lightBrush = New-Object Drawing.SolidBrush -ArgumentList ([Drawing.Color]::FromArgb(240,217,181))
$darkBrush  = New-Object Drawing.SolidBrush -ArgumentList ([Drawing.Color]::FromArgb(181,136,99))
$selBrush   = New-Object Drawing.SolidBrush -ArgumentList ([Drawing.Color]::FromArgb(160,210,90))
$dotBrush   = New-Object Drawing.SolidBrush -ArgumentList ([Drawing.Color]::FromArgb(30,30,30,120))

function Update-Status {
    if($board.WhiteToMove -eq $script:HumanIsWhite){ $lblStatus.Text = "Your move" } else { $lblStatus.Text = "Computer thinking..." }
}

function ModelSqFromPoint([Drawing.Point]$pt){
    $vf = [Math]::Floor($pt.X / $tile)
    $vr = 7 - [Math]::Floor($pt.Y / $tile)
    if($vf -lt 0 -or $vf -gt 7 -or $vr -lt 0 -or $vr -gt 7){ return -1 }
    if($script:HumanIsWhite){ return $vr*8 + $vf } else { return (7-$vr)*8 + (7-$vf) }
}

function DrawPiece($g, [char]$piece, [int]$cx, [int]$cy){
    if($piece -eq '.' ){ return }
    if($script:SpritesOk -and $script:PieceBmp.ContainsKey($piece) -and $script:PieceBmp[$piece]){
        $bmp = $script:PieceBmp[$piece]
        $dest = New-Object Drawing.Rectangle ($cx - [int]($bmp.Width/2)), ($cy - [int]($bmp.Height/2)), $bmp.Width, $bmp.Height
        $g.DrawImageUnscaledAndClipped($bmp, $dest)  # no scaling -> crisp
    } else {
        $g.DrawString($glyph[[char]$piece], $font, [Drawing.Brushes]::Black, $cx, $cy, $sf)
    }
}


function Draw-Board([object]$s,[object]$e){
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    for($vr=0; $vr -lt 8; $vr++){
        for($vf=0; $vf -lt 8; $vf++){
            $x=$vf*$tile; $y=(7-$vr)*$tile
            if((($vr+$vf)%2) -eq 0){
                $g.FillRectangle($lightBrush, $x, $y, $tile, $tile)
            } else {
                $g.FillRectangle($darkBrush, $x, $y, $tile, $tile)
            }

            # model square for this view
            $msq = if($script:HumanIsWhite){ $vr*8+$vf } else { (7-$vr)*8 + (7-$vf) }

            # mark legal targets
            if($script:LegalTos -and ($script:LegalTos -contains $msq)){
                $g.FillEllipse($dotBrush, $x+$tile/2-9, $y+$tile/2-9, 18, 18)
            }

            # piece (skip if dragging from here)
            $piece = $board.S[$msq]
            if($piece -ne '.' -and -not ($script:Dragging -and $msq -eq $script:DragFrom)){
                DrawPiece -g $g -piece $piece -cx ($x+$tile/2) -cy ($y+$tile/2)
            }
        }
    }
    if($script:Dragging -and $script:DragPiece -ne 0){
        DrawPiece -g $g -piece $script:DragPiece -cx $script:DragPoint.X -cy $script:DragPoint.Y
    }
}
$panel.Add_Paint({ Draw-Board $args[0] $args[1] })

function Refresh-Panel { $panel.Invalidate() }

function Start-NewGame {
    $board.Reset()
    $script:HumanIsWhite = ($sideCombo.SelectedIndex -eq 0)
    $script:Dragging=$false; $script:DragFrom=-1; $script:DragPiece=[char]0; $script:LegalTos=@()
    Refresh-Panel; Update-Status
    if(-not $script:HumanIsWhite){
        # Computer (White) makes the first move synchronously
        $best = $engine.GetBestMove($board)
        if($best.From -ne -1){ $board.MakeMove($best) }
        Refresh-Panel; Update-Status
    }
}

# Mouse handlers (drag)
$panel.Add_MouseDown({
    if($board.WhiteToMove -ne $script:HumanIsWhite){ return }
    $sq = ModelSqFromPoint (New-Object Drawing.Point -ArgumentList $args[1].X, $args[1].Y)
    if($sq -lt 0){ return }
    $p = $board.S[$sq]
    if($p -eq '.'){ return }
    $isW = [TinyCsChess.Board]::IsWhite($p)
    if(($script:HumanIsWhite -and $isW) -or ((-not $script:HumanIsWhite) -and (-not $isW))){
        $script:DragFrom = $sq
        $script:DragPiece = $p
        $script:Dragging = $true
        $panel.Capture = $true
        # collect legal destinations from here
        $script:LegalTos = @()
        foreach($m in $board.GetLegalMoves()){ if($m.From -eq $sq){ $script:LegalTos += $m.To } }
        $script:DragPoint = New-Object Drawing.Point -ArgumentList $args[1].X, $args[1].Y
        Refresh-Panel
    }
})

$panel.Add_MouseMove({
    if(-not $script:Dragging){ return }
    $script:DragPoint = New-Object Drawing.Point -ArgumentList $args[1].X, $args[1].Y
    Refresh-Panel
})

$panel.Add_MouseUp({
    if(-not $script:Dragging){ return }
    $panel.Capture = $false
    $drop = ModelSqFromPoint (New-Object Drawing.Point -ArgumentList $args[1].X, $args[1].Y)
    $made=$false
    if($drop -ge 0){
        foreach($m in $board.GetLegalMoves()){
            if($m.From -eq $script:DragFrom -and $m.To -eq $drop){
                $board.MakeMove($m); $made=$true; break
            }
        }
    }
    $script:Dragging=$false; $script:DragFrom=-1; $script:DragPiece=[char]0; $script:LegalTos=@()
    Refresh-Panel; Update-Status
    if($made){
        # end detection
        $legal = $board.GetLegalMoves()
        if($legal.Count -eq 0){
            if($board.IsInCheck($board.WhiteToMove)){
                [Windows.Forms.MessageBox]::Show("Checkmate! " + ($(if($board.WhiteToMove){"Computer"}else{"You"})) + " win(s).") | Out-Null
            } else {
                [Windows.Forms.MessageBox]::Show("Stalemate.") | Out-Null
            }
            Start-NewGame; return
        }
        # computer reply (synchronous for reliability)
        $best = $engine.GetBestMove($board)
        if($best.From -ne -1){ $board.MakeMove($best) }
        Refresh-Panel; Update-Status

        # end after computer move
        $legal = $board.GetLegalMoves()
        if($legal.Count -eq 0){
            if($board.IsInCheck($board.WhiteToMove)){
                [Windows.Forms.MessageBox]::Show("Checkmate! " + ($(if($board.WhiteToMove){"You"}else{"Computer"})) + " win(s).") | Out-Null
            } else {
                [Windows.Forms.MessageBox]::Show("Stalemate.") | Out-Null
            }
            Start-NewGame; return
        }
    }
})

# UI wire-up
$btnNew.Add_Click({ Start-NewGame })
$form.Add_Shown({
    Initialize-Sprites -TileSize $tile
    Start-NewGame
})

# Dispose graphics resources on close
$form.Add_FormClosed({
    if($script:SpriteSheet){ $script:SpriteSheet.Dispose() }
    foreach($k in $script:PieceBmp.Keys){
        $bmp = $script:PieceBmp[$k]
        if($bmp -ne $null){ $bmp.Dispose() }
    }
    $lightBrush.Dispose(); $darkBrush.Dispose(); $selBrush.Dispose(); $dotBrush.Dispose()
    $font.Dispose()
})

[void][Windows.Forms.Application]::EnableVisualStyles()
[void][Windows.Forms.Application]::Run($form)
