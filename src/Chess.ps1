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

    public static class Globals
    {
        public static bool VariantGiveaway = false;
        public static bool VariantHorde = false;
        public static bool VariantCastle = false;
        public static bool VariantBulwark  = false;
        public static bool VariantCentaur = false;
    }


    public class Board
    {
        public char[] S = new char[64]; // model index: rank*8+file, rank 0 = white home rank
        public bool WhiteToMove = true;
        public int Half; public int Full;

        // --- Castling rights ---
        public bool WK=true, WQ=true, BK=true, BQ=true; // white/black king/queen side

        public Board(){ Reset(); }

        public void Reset()
        {
            string start;

            if (TinyCsChess.Globals.VariantHorde)
            {
                start =
                    "PPPPPPPP" +
                    "PPPPPPPP" +
                    "PPPPPPPP" +
                    "PPPPPPPP" +
                    ".PP..PP." +
                    "........" +
                    "pppppppp" +
                    "rnbqkbnr";
            }
            else if (TinyCsChess.Globals.VariantCastle)
            {
                start =
                    "RNBQKBNR" +
                    "PPPPPPPP" +
                    "........" +
                    "........" +
                    "........" +
                    "p......p" +
                    "rppppppr" +
                    "rnbqkbnr";
            }
            else if (TinyCsChess.Globals.VariantBulwark)
            {
                start =
                    "RNBQKBNR" +
                    "PPPPPPPP" +
                    "........" +
                    "........" +
                    "........" +
                    "...pp..." +
                    "pppqkppp" +
                    "rrrrrrrr";
            }
            else if (TinyCsChess.Globals.VariantCentaur)
            {
                start =
                    "RCBQKBCR" +
                    "PPPPPPPP" +
                    "........" +
                    "........" +
                    "........" +
                    "........" +
                    "rppppppp" +
                    "rcbqkbcr";
            }
            else
            {
                // Standard chess layout
                start =
                    "RNBQKBNR" +
                    "PPPPPPPP" +
                    "........" +
                    "........" +
                    "........" +
                    "........" +
                    "pppppppp" +
                    "rnbqkbnr";
            }

            for (int i = 0; i < 64; i++) S[i] = start[i];
            WhiteToMove = true; Half = 0; Full = 1;
            WK = WQ = BK = BQ = true;
        }


        public Board Copy()
        {
            Board b = new Board();
            Array.Copy(S, b.S, 64);
            b.WhiteToMove = WhiteToMove;
            b.Half = Half; b.Full = Full;
            b.WK = WK; b.WQ = WQ; b.BK = BK; b.BQ = BQ;
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

            // Detect castling by king two-square move
            bool isKing = (char.ToLower(piece) == 'k');
            int fromF = FileOf(m.From), toF = FileOf(m.To);
            bool castle = isKing && Math.Abs(toF - fromF) == 2;

            // Move piece
            S[m.To] = piece;
            S[m.From] = '.';

            // Auto-queen on promotion request or reaching last rank
            if(m.Promote!='\0') S[m.To]=m.Promote;
            else if(char.ToLower(piece)=='p'){
                int r = RankOf(m.To);
                if(r==7 && piece=='P') S[m.To]='Q'; // White reaches top
                if(r==0 && piece=='p') S[m.To]='q'; // Black reaches bottom
            }

            // --- Handle castling rook move ---
            if(castle){
                // White
                if(piece=='K'){
                    // King from e1(4) to g1(6) -> rook h1(7) to f1(5); e1 to c1(2) -> rook a1(0) to d1(3)
                    if(m.To == 6){ S[5] = 'R'; S[7] = '.'; }         // K-side
                    else if(m.To == 2){ S[3] = 'R'; S[0] = '.'; }    // Q-side
                }
                // Black
                else if(piece=='k'){
                    // e8(60)->g8(62): h8(63)->f8(61); e8->c8(58): a8(56)->d8(59)
                    if(m.To == 62){ S[61] = 'r'; S[63] = '.'; }      // K-side
                    else if(m.To == 58){ S[59] = 'r'; S[56] = '.'; } // Q-side
                }
            }

            // --- Update castling rights on king/rook moves or rook capture ---
            // If king moves, lose both sides
            if(piece=='K'){ WK=false; WQ=false; }
            if(piece=='k'){ BK=false; BQ=false; }

            // If rook moves from original squares
            if(piece=='R'){
                if(m.From==7) WK=false;      // h1
                else if(m.From==0) WQ=false; // a1
            }
            if(piece=='r'){
                if(m.From==63) BK=false;     // h8
                else if(m.From==56) BQ=false;// a8
            }

            // If a rook is captured on its original square, disable that side
            if(captured=='R'){
                if(m.To==7) WK=false;
                else if(m.To==0) WQ=false;
            }
            if(captured=='r'){
                if(m.To==63) BK=false;
                else if(m.To==56) BQ=false;
            }

            // Halfmove clock
            if(char.ToLower(piece)=='p' || captured!='.') Half=0; else Half++;
            if(!WhiteToMove) Full++;
            WhiteToMove = !WhiteToMove;
        }

        public List<Move> GetLegalMoves()
        {
            List<Move> ps = GetPseudo();
            List<Move> legal = new List<Move>();
            bool giveaway = TinyCsChess.Globals.VariantGiveaway;

            for (int i = 0; i < ps.Count; i++)
            {
                Move m = ps[i];
                Board c = Copy();
                c.MakeMove(m);

                if (giveaway)
                    legal.Add(m); // no check filtering
                else if (!c.IsInCheck(!c.WhiteToMove))
                    legal.Add(m);
            }

            if (giveaway)
            {
                // Captures compulsory
                List<Move> captures = new List<Move>();
                for (int i = 0; i < legal.Count; i++)
                {
                    char victim = S[legal[i].To];
                    if (victim != '.')
                        captures.Add(legal[i]);
                }
                if (captures.Count > 0)
                    return captures;
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
                    int dir = w ? +1 : -1;   // white forward increases rank
                    int startRank = w? 1 : 6;
                    int promoteRank = w? 7 : 0;

                    int fwd = sq + dir*8;
                    if(fwd>=0 && fwd<64 && S[fwd]=='.'){
                        
                        if (RankOf(fwd) == promoteRank) {
                            char[] opts = (w ? new char[]{'Q','R','B','N','K'} : new char[]{'q','r','b','n','k'});
                            for (int pi = 0; pi < opts.Length; pi++)
                                mv.Add(new Move(sq, fwd, opts[pi]));
                        } else {
                            mv.Add(new Move(sq, fwd, '\0'));
                        }

                        int dbl = sq + dir*16;
                        if(r==startRank && S[dbl]=='.') mv.Add(new Move(sq,dbl,'\0'));
                    }
                    int[] cdirs = new int[]{ dir*8-1, dir*8+1 };
                    for(int k=0;k<2;k++){
                        int to=sq+cdirs[k];
                        if(to>=0 && to<64){
                            int tf=FileOf(to);
                            if(Math.Abs(tf-f)==1 && S[to]!='.' && IsWhite(S[to])!=w){
                                
                                if (RankOf(to) == promoteRank) {
                                    char[] opts = (w ? new char[]{'Q','R','B','N','K'} : new char[]{'q','r','b','n','k'});
                                    for (int pi = 0; pi < opts.Length; pi++)
                                        mv.Add(new Move(sq, to, opts[pi]));
                                } else {
                                    mv.Add(new Move(sq, to, '\0'));
                                }

                            }
                        }
                    }
                }
                else if(pl=='n' || pl=='c'){  // centaur moves like knight
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
                    if(pl=='c'){ // centaur also moves like king
                        int[] kingOffsets = new int[]{-9,-8,-7,-1,1,7,8,9};
                        for(int i=0;i<kingOffsets.Length;i++){
                            int to=sq+kingOffsets[i];
                            if(to>=0 && to<64){
                                int tf=FileOf(to), tr=RankOf(to);
                                if(Math.Abs(tf-f)<=1 && Math.Abs(tr-r)<=1){
                                    char t=S[to];
                                    if(t=='.' || IsWhite(t)!=IsWhite(p)) mv.Add(new Move(sq,to,'\0'));
                                }
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
                        int max = (pl=='k')?1:7;
                        for(int d=0; d<dirs.Length; d++){
                            int df=dirs[d][0], dr=dirs[d][1];
                            for(int step=1; step<=max; step++){
                                int nf=f+df*step, nr=r+dr*step;
                                if(nf<0||nf>7||nr<0||nr>7) break;
                                int to=nr*8+nf; char t=S[to];
                                if(t=='.'){ mv.Add(new Move(sq,to,'\0')); }
                                else { if(IsWhite(t)!=IsWhite(p)) mv.Add(new Move(sq,to,'\0')); break; }
                            }
                        }
                    }

                    // --- Castling pseudo (only when king) ---
                    if(pl=='k'){
                        // Don't allow if currently in check
                        if(!IsInCheck(WhiteToMove)){
                            if(IsWhite(p)){
                                // White king on e1 (4)
                                if(sq==4){
                                    // King-side: f1(5), g1(6) empty; rook at h1(7); rights; squares not attacked
                                    if(WK && S[5]=='.' && S[6]=='.' && S[7]=='R' &&
                                       !IsSquareAttackedBy(false,5) && !IsSquareAttackedBy(false,6))
                                    {
                                        mv.Add(new Move(4,6,'\0'));
                                    }
                                    // Queen-side: d1(3), c1(2) empty; rook at a1(0); rights; squares not attacked; b1(1) can be occupied, that's fine
                                    if(WQ && S[3]=='.' && S[2]=='.' && S[0]=='R' &&
                                       S[1]=='.' && // standard rules: b1 must also be empty to move rook across
                                       !IsSquareAttackedBy(false,3) && !IsSquareAttackedBy(false,2))
                                    {
                                        mv.Add(new Move(4,2,'\0'));
                                    }
                                }
                            } else {
                                // Black king on e8 (60)
                                if(sq==60){
                                    // King-side: f8(61), g8(62) empty; rook at h8(63)
                                    if(BK && S[61]=='.' && S[62]=='.' && S[63]=='r' &&
                                       !IsSquareAttackedBy(true,61) && !IsSquareAttackedBy(true,62))
                                    {
                                        mv.Add(new Move(60,62,'\0'));
                                    }
                                    // Queen-side: d8(59), c8(58) empty; rook at a8(56)
                                    if(BQ && S[59]=='.' && S[58]=='.' && S[56]=='r' &&
                                       S[57]=='.' &&
                                       !IsSquareAttackedBy(true,59) && !IsSquareAttackedBy(true,58))
                                    {
                                        mv.Add(new Move(60,58,'\0'));
                                    }
                                }
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

        // Is target square attacked by a given side (whiteAttackers==true => white attacks)
        public bool IsSquareAttackedBy(bool whiteAttackers, int target)
        {
            for(int sq=0; sq<64; sq++){
                char p=S[sq]; if(p=='.') continue;
                if(IsWhite(p) != whiteAttackers) continue;
                if(CanAttack(sq, target)) return true;
            }
            return false;
        }

        private bool CanAttack(int from, int to)
        {
            char p = S[from];
            char pl = char.ToLower(p);
            int ff = FileOf(from), fr = RankOf(from);
            int tf = FileOf(to),   tr = RankOf(to);
            int df = tf - ff,      dr = tr - fr;

            if (pl == 'p')
            {
                bool w = IsWhite(p);
                return (w && dr == 1 && Math.Abs(df) == 1) || (!w && dr == -1 && Math.Abs(df) == 1);
            }

            if (pl == 'n')
                return (Math.Abs(df) == 2 && Math.Abs(dr) == 1) || (Math.Abs(df) == 1 && Math.Abs(dr) == 2);

            if (pl == 'c')
            {
                // Centaur: combines knight + king attack patterns
                bool knight = (Math.Abs(df) == 2 && Math.Abs(dr) == 1) || (Math.Abs(df) == 1 && Math.Abs(dr) == 2);
                bool king   = Math.Abs(df) <= 1 && Math.Abs(dr) <= 1;
                return knight || king;
            }

            if (pl == 'k')
                return Math.Abs(df) <= 1 && Math.Abs(dr) <= 1;

            bool diag  = Math.Abs(df) == Math.Abs(dr);
            bool ortho = (df == 0 || dr == 0);

            if (pl == 'b' && !diag) return false;
            if (pl == 'r' && !ortho) return false;
            if (pl == 'q' && !(diag || ortho)) return false;

            int sxf = (df == 0) ? 0 : (df / Math.Abs(df));
            int sxr = (dr == 0) ? 0 : (dr / Math.Abs(dr));
            int steps = Math.Max(Math.Abs(df), Math.Abs(dr));

            for (int i = 1; i < steps; i++)
            {
                int sq = (fr + i * sxr) * 8 + (ff + i * sxf);
                if (S[sq] != '.') return false;
            }

            return true;
        }


        public int Evaluate()
        {
            int score = 0;
            for (int i = 0; i < 64; i++)
            {
                char p = S[i];
                if (p == '.') continue;

                int val = 0;
                switch (char.ToLower(p))
                {
                    case 'p': val = 100; break;
                    case 'n': val = 320; break;
                    case 'b': val = 330; break;
                    case 'r': val = 500; break;
                    case 'q': val = 900; break;
                    case 'k': val = 20000; break;
                    case 'c': val = 650; break; // Centaur = Knight + King hybrid
                }

                if (IsWhite(p))
                    score += val;
                else
                    score -= val;
            }
            return score;
        }

        // -------- Zobrist hashing (TT key) --------
        static ulong[] ZPieces = null; // 64 * 12
        static ulong ZSide = 0;
        static ulong ZWK=0, ZWQ=0, ZBK=0, ZBQ=0; // castling rights

        static int PieceIndex(char p){
            switch(p){
                case 'P': return 0;  case 'N': return 1;  case 'B': return 2;  case 'R': return 3;  case 'Q': return 4;  case 'K': return 5;
                case 'p': return 6;  case 'n': return 7;  case 'b': return 8;  case 'r': return 9;  case 'q': return 10; case 'k': return 11;
                default:  return -1;
            }
        }

        static void EnsureZobrist(){
            if(ZPieces!=null) return;
            ZPieces = new ulong[64*12];
            System.Random rng = new System.Random(881726454); // fixed seed
            for(int i=0;i<64*12;i++){
                byte[] b = new byte[8];
                rng.NextBytes(b);
                ZPieces[i] = System.BitConverter.ToUInt64(b,0);
            }
            byte[] sb = new byte[8];
            rng.NextBytes(sb); ZSide = System.BitConverter.ToUInt64(sb,0);
            rng.NextBytes(sb); ZWK   = System.BitConverter.ToUInt64(sb,0);
            rng.NextBytes(sb); ZWQ   = System.BitConverter.ToUInt64(sb,0);
            rng.NextBytes(sb); ZBK   = System.BitConverter.ToUInt64(sb,0);
            rng.NextBytes(sb); ZBQ   = System.BitConverter.ToUInt64(sb,0);
        }

        public ulong ComputeHash(){
            EnsureZobrist();
            ulong h = 0UL;
            for(int sq=0; sq<64; sq++){
                int pi = PieceIndex(S[sq]);
                if(pi>=0) h ^= ZPieces[pi*64 + sq];
            }
            if(WhiteToMove) h ^= ZSide;
            if(WK) h ^= ZWK; if(WQ) h ^= ZWQ; if(BK) h ^= ZBK; if(BQ) h ^= ZBQ;
            return h;
        }

        // Legal captures only (used by quiescence)
        public System.Collections.Generic.List<Move> GetLegalCaptures(){
            var all = GetLegalMoves();
            var caps = new System.Collections.Generic.List<Move>(16);
            for(int i=0;i<all.Count;i++){
                Move m = all[i];
                if(S[m.To] != '.') caps.Add(m);
            }
            return caps;
        }
    }

    public class Engine
    {
        public int MaxDepth = 4;       // can try 
        public int TimeMs   = 0;       // not used here
        const int INF = 1000000000;

        // --- Transposition table ---
        class TTEntry {
            public ulong Key;
            public int Depth;
            public int Score;
            public byte Flag; // 0 = EXACT, 1 = LOWER, 2 = UPPER
            public Move Best;
        }
        System.Collections.Generic.Dictionary<ulong, TTEntry> TT =
            new System.Collections.Generic.Dictionary<ulong, TTEntry>(1<<20); // ~1M logical capacity

        // --- Move ordering helpers ---
        int[,] History = new int[64,64];   // from,to
        Move[,] Killers = new Move[256,2]; // per-ply two killers

        static int PieceVal(char p)
        {
            switch (char.ToLower(p))
            {
                case 'p': return 100;
                case 'n': return 320;
                case 'b': return 330;
                case 'r': return 500;
                case 'q': return 900;
                case 'k': return 20000;
                case 'c': return 650; // Centaur piece value
            }
            return 0;
        }

        int ScoreMove(TinyCsChess.Board b, Move m, Move hashMove, int ply){
            if(hashMove!=null && m.From==hashMove.From && m.To==hashMove.To && m.Promote==hashMove.Promote) return 900000000;

            char victim = b.S[m.To];
            if(victim!='.'){
                int att = PieceVal(b.S[m.From]);
                int vic = PieceVal(victim);
                return 800000000 + (vic*1000 - att);
            }

            if(Killers[ply,0]!=null && m.From==Killers[ply,0].From && m.To==Killers[ply,0].To) return 700000000;
            if(Killers[ply,1]!=null && m.From==Killers[ply,1].From && m.To==Killers[ply,1].To) return 699000000;

            return History[m.From,m.To];
        }

        void NoteKiller(int ply, Move m){
            if(Killers[ply,0]==null || !(Killers[ply,0].From==m.From && Killers[ply,0].To==m.To)){
                Killers[ply,1] = Killers[ply,0];
                Killers[ply,0] = m;
            }
        }

        void NoteHistory(Move m, int depth){
            int add = depth*depth;
            int v = History[m.From,m.To] + add;
            if(v < 900000000) History[m.From,m.To] = v;
        }

        int EvalSideToMove(TinyCsChess.Board b)
        {
            int s = b.Evaluate() * (b.WhiteToMove ? 1 : -1);
            if (TinyCsChess.Globals.VariantGiveaway)
                s = -s; // fewer pieces is better
            return s;
        }


        // --- Quiescence search (captures only) ---
        int Quiesce(TinyCsChess.Board b, int alpha, int beta){
            int stand = EvalSideToMove(b);

            if(stand >= beta) return beta;
            if(alpha < stand) alpha = stand;

            var caps = b.GetLegalCaptures();
            caps.Sort(delegate(Move a, Move c){
                int sa = 0, sc = 0;
                char va = b.S[a.To], vc = b.S[c.To];
                if(va!='.') sa = PieceVal(va)*1000 - PieceVal(b.S[a.From]);
                if(vc!='.') sc = PieceVal(vc)*1000 - PieceVal(b.S[c.From]);
                return sc.CompareTo(sa);
            });

            for(int i=0;i<caps.Count;i++){
                Move m = caps[i];
                TinyCsChess.Board nb = b.Copy();
                nb.MakeMove(m);
                int score = -Quiesce(nb, -beta, -alpha);
                if(score >= beta) return beta;
                if(score > alpha) alpha = score;
            }
            return alpha;
        }

        // --- AlphaBeta with TT, LMR, futility, move ordering ---
        int AlphaBeta(TinyCsChess.Board b, int depth, int alpha, int beta, int ply, Move prevBest)
        {
            int origAlpha = alpha;
            int origBeta  = beta;

            bool inCheck = b.IsInCheck(b.WhiteToMove);
            if(depth <= 0){
                return Quiesce(b, alpha, beta);
            }

            // TT probe
            ulong key = b.ComputeHash();
            TTEntry te;
            if(TT.TryGetValue(key, out te)){
                if(te.Depth >= depth){
                    if(te.Flag==0) return te.Score;
                    if(te.Flag==1 && te.Score > alpha) alpha = te.Score; // LOWER
                    if(te.Flag==2 && te.Score < beta)  beta  = te.Score; // UPPER
                    if(alpha >= beta) return te.Score;
                }
                if(prevBest==null) prevBest = te.Best;
            }

            var moves = b.GetLegalMoves();
            if (moves == null || moves.Count == 0)
            {
                if (TinyCsChess.Globals.VariantHorde)
                {
                    // Horde special end: if no white pieces, black wins; if black king gone, white wins
                    bool whiteExists = false, blackKingAlive = false;
                    for (int i = 0; i < 64; i++)
                    {
                        char p = b.S[i];
                        if (p == 'k') blackKingAlive = true;
                        if (TinyCsChess.Board.IsWhite(p)) whiteExists = true;
                    }
                    if (!whiteExists) return -20000 + ply;
                    if (!blackKingAlive) return +20000 - ply;
                }

                if (TinyCsChess.Globals.VariantGiveaway)
                    return +20000 - ply;
                if (inCheck)
                    return -20000 + ply;
                return 0;
            }

            moves.Sort(delegate(Move x, Move y){
                int sx = ScoreMove(b, x, prevBest, ply);
                int sy = ScoreMove(b, y, prevBest, ply);
                return sy.CompareTo(sx);
            });

            int bestScore = -INF;
            Move bestMove = null;


            bool allowFutility = (!inCheck && depth <= 2);
            int movesSearched = 0;

            for(int i=0;i<moves.Count;i++){
                Move m = moves[i];
                bool isCapture = (b.S[m.To] != '.');

                // Late-move reduction for quiet moves
                int reduction = 0;
                if(depth >= 3 && !isCapture && movesSearched >= 4){
                    reduction = 1;
                }

                // Futility near leaves for quiets
                if(allowFutility && !isCapture && depth==1){
                    int stand = b.Evaluate() * (b.WhiteToMove?1:-1);
                    if(stand + 150 < alpha){
                        movesSearched++;
                        continue;
                    }
                }

                TinyCsChess.Board nb = b.Copy();
                nb.MakeMove(m);

                int score;
                if(reduction>0){
                    score = -AlphaBeta(nb, depth-1-reduction, -alpha-1, -alpha, ply+1, null);
                    if(score > alpha){
                        score = -AlphaBeta(nb, depth-1, -beta, -alpha, ply+1, null);
                    }
                } else {
                    score = -AlphaBeta(nb, depth-1, -beta, -alpha, ply+1, null);
                }

                movesSearched++;

                if(score > bestScore){
                    bestScore = score;
                    bestMove = m;
                    if(score > alpha){
                        alpha = score;
                        if(alpha >= beta){
                            if(!isCapture){
                                NoteKiller(ply, m);
                                NoteHistory(m, depth);
                            }
                            break;
                        }
                    }
                }
            }

            // Store in TT with correct node type
            byte flag = 0; // EXACT
            if(bestScore <= origAlpha) flag = 2; // UPPER
            else if(bestScore >= origBeta) flag = 1; // LOWER

            TTEntry store = new TTEntry();
            store.Key = key; store.Depth = depth; store.Score = bestScore; store.Flag = flag; store.Best = bestMove;
            TT[key] = store;

            return bestScore;
        }

        // --- Iterative deepening with aspiration windows ---
        public Move GetBestMove(Board b)
        {
            Move best = null;
            int guess = b.Evaluate() * (b.WhiteToMove?1:-1);
            int alpha = -INF, beta = INF;

            for(int d=1; d<=MaxDepth; d++){
                if(d>=3){
                    int asp = 50 + 50*d; // widen with depth
                    alpha = guess - asp;
                    beta  = guess + asp;
                } else {
                    alpha = -INF; beta = INF;
                }

                int score = AlphaBeta(b, d, alpha, beta, 0, best);

                if(score <= alpha){
                    score = AlphaBeta(b, d, -INF, beta, 0, best);
                } else if(score >= beta){
                    score = AlphaBeta(b, d, alpha, INF, 0, best);
                }

                TTEntry te;
                if(TT.TryGetValue(b.ComputeHash(), out te)){
                    if(te.Best!=null) best = te.Best;
                    guess = score;
                }
            }

            if(best==null){
                var ms = b.GetLegalMoves();
                if(ms.Count==0) return new Move(-1,-1,'\0');
                best = ms[0];
            }
            return best;
        }

        public static class SpriteHelper
        {
            public static System.Drawing.Bitmap LoadBitmapFromUrl(string url)
            {
                var request = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(url);
                request.AllowAutoRedirect = true;
                request.UserAgent = "PowerShellChess/1.0";
                request.Timeout = 10000;

                using (var response = (System.Net.HttpWebResponse)request.GetResponse())
                using (var responseStream = response.GetResponseStream())
                {
                    if (responseStream == null)
                        throw new System.Exception("Null response stream for " + url);

                    using (var ms = new System.IO.MemoryStream())
                    {
                        responseStream.CopyTo(ms);
                        ms.Position = 0;
                        return new System.Drawing.Bitmap(ms);
                    }
                }
            }
        }




        public static System.Drawing.Bitmap LoadBitmapFromBase64(string base64)
        {
            byte[] bytes = Convert.FromBase64String(base64);
            using (var ms = new System.IO.MemoryStream(bytes))
                return new System.Drawing.Bitmap(ms);
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
$engine.MaxDepth = 7   # increased by +2 plies from previous 5 -> 7

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

$lblVariant = New-Object Windows.Forms.Label
$lblVariant.Text = "Variant:"
$lblVariant.AutoSize = $true
$lblVariant.Location = New-Object Drawing.Point -ArgumentList 370, 8

$variantCombo = New-Object Windows.Forms.ComboBox
$variantCombo.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
[void]$variantCombo.Items.Add("Standard")
[void]$variantCombo.Items.Add("Giveaway")
[void]$variantCombo.Items.Add("Horde")
[void]$variantCombo.Items.Add("Castle")
[void]$variantCombo.Items.Add("Centaur")
[void]$variantCombo.Items.Add("Bulwark")


$variantCombo.SelectedIndex = 0
$variantCombo.Location = New-Object Drawing.Point -ArgumentList 440, 4
$variantCombo.Width = 90

$form.Controls.AddRange(@($lblVariant, $variantCombo))

$script:Variant = "Standard"
$variantCombo.Add_SelectedIndexChanged({
    $script:Variant = $variantCombo.SelectedItem
})

function Sync-Variant {
    [TinyCsChess.Globals]::VariantGiveaway = ($variantCombo.SelectedItem -eq 'Giveaway')
    [TinyCsChess.Globals]::VariantHorde    = ($variantCombo.SelectedItem -eq 'Horde')
    [TinyCsChess.Globals]::VariantCastle   = ($variantCombo.SelectedItem -eq 'Castle')
    [TinyCsChess.Globals]::VariantBulwark  = ($variantCombo.SelectedItem -eq 'Bulwark')
    [TinyCsChess.Globals]::VariantCentaur  = ($variantCombo.SelectedItem -eq 'Centaur')

    if ([TinyCsChess.Globals]::VariantCentaur) {
        Ensure-CentaurSprites -TileSize $tile
    }
}

$variantCombo.Add_SelectedIndexChanged({ Sync-Variant })


$btnNew = New-Object Windows.Forms.Button
$btnNew.Text = "New Game"
$btnNew.Location = New-Object Drawing.Point -ArgumentList 170, 3
$btnNew.Width = 90

$btnFlip = New-Object Windows.Forms.Button
$btnFlip.Text = "Flip Board"
$btnFlip.Location = New-Object Drawing.Point -ArgumentList 270, 3
$btnFlip.Width = 90

$form.Controls.AddRange(@($lblSide,$sideCombo,$btnNew,$btnFlip,$lblStatus,$panel))
$script:FlippedView = $false
$btnFlip.Add_Click({
    $script:FlippedView = -not $script:FlippedView
    Refresh-Panel
})


$lblStatus = New-Object Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object Drawing.Point -ArgumentList 270, 8

# Use our flicker-free panel
$panel = New-Object DbPanel
$panel.Location = New-Object Drawing.Point -ArgumentList 0, 32
$panel.Size = New-Object Drawing.Size -ArgumentList (8*$tile), (8*$tile)
$panel.BackColor = [Drawing.Color]::FromArgb(230,230,230)
$panel.Cursor = [Windows.Forms.Cursors]::Hand


# === HISTORY PANE (non-invasive; correct move tracking and SAN display) ===

# safe arrow creation (ASCII-only source)
$arrowLeft  = [string][char]0x2B9C
$arrowRight = [string][char]0x2B9E

# layout constants
$panelHistoryWidth = 200
$baseBoardWidth  = 8 * $tile
$baseBoardHeight = 8 * $tile + 56

# state
$script:MoveHistory = @()
$script:ReviewIndex = -1
$script:LastHash = $null
$script:LastBoard = $null

# UI construction
$panelHistory = New-Object Windows.Forms.Panel
$panelHistory.Size = New-Object Drawing.Size $panelHistoryWidth, $baseBoardHeight
$panelHistory.Location = New-Object Drawing.Point ($baseBoardWidth + 2), 0
$panelHistory.BackColor = [Drawing.Color]::FromArgb(240,240,240)
$panelHistory.Visible = $false
$form.Controls.Add($panelHistory)

$lblHistory = New-Object Windows.Forms.Label
$lblHistory.Text = "Move History"
$lblHistory.Font = New-Object Drawing.Font ("Segoe UI", 10, [Drawing.FontStyle]::Bold)
$lblHistory.AutoSize = $true
$lblHistory.Location = New-Object Drawing.Point 8, 8
$panelHistory.Controls.Add($lblHistory)

$listHistory = New-Object Windows.Forms.ListBox
$listHistory.Location = New-Object Drawing.Point 8, 30
$listHistory.Size = New-Object Drawing.Size 180, 400
$panelHistory.Controls.Add($listHistory)

$btnBack = New-Object Windows.Forms.Button
$btnBack.Text = "$arrowLeft Prev"
$btnBack.Size = New-Object Drawing.Size 85, 25
$btnBack.Location = New-Object Drawing.Point 8, 440
$panelHistory.Controls.Add($btnBack)

$btnForward = New-Object Windows.Forms.Button
$btnForward.Text = "Next $arrowRight"
$btnForward.Size = New-Object Drawing.Size 85, 25
$btnForward.Location = New-Object Drawing.Point 100, 440
$panelHistory.Controls.Add($btnForward)

# collapse toggle
$btnTogglePane = New-Object Windows.Forms.Button
$btnTogglePane.Text = $arrowRight
$btnTogglePane.Width = 30
$btnTogglePane.Height = 25
$btnTogglePane.Location = New-Object Drawing.Point ($baseBoardWidth - 35), 3
$form.Controls.Add($btnTogglePane)
$btnTogglePane.BringToFront()

function Adjust-FormSize {
    if ($panelHistory.Visible) {
        $panelHistory.Location = New-Object Drawing.Point ($baseBoardWidth + 2), 0
        $form.ClientSize = New-Object Drawing.Size ($baseBoardWidth + $panelHistoryWidth + 2), $baseBoardHeight
    } else {
        $form.ClientSize = New-Object Drawing.Size $baseBoardWidth, $baseBoardHeight
    }
    $panel.BringToFront()
    $btnTogglePane.BringToFront()
}

$btnTogglePane.Add_Click({
    $panelHistory.Visible = -not $panelHistory.Visible
    $btnTogglePane.Text = if ($panelHistory.Visible) { $arrowLeft } else { $arrowRight }
    Adjust-FormSize
})

# history helpers
function Record-PositionFromBoard {
    $script:MoveHistory += ,$board.Copy()
    $script:ReviewIndex = $script:MoveHistory.Count - 1
    $listHistory.Items.Add(("Move {0}" -f $script:ReviewIndex))
    $listHistory.SelectedIndex = $script:ReviewIndex
    $panel.Enabled = ($script:ReviewIndex -eq ($script:MoveHistory.Count - 1))
}

function Load-Position([int]$index) {
    if ($index -lt 0 -or $index -ge $script:MoveHistory.Count) { return }
    $b = $script:MoveHistory[$index]
    $board.S = [char[]]$b.S.Clone()
    $board.WhiteToMove = $b.WhiteToMove
    $board.WK=$b.WK; $board.WQ=$b.WQ; $board.BK=$b.BK; $board.BQ=$b.BQ
    $board.Half=$b.Half; $board.Full=$b.Full
    $script:ReviewIndex = $index
    $listHistory.SelectedIndex = $index
    $panel.Enabled = ($script:ReviewIndex -eq ($script:MoveHistory.Count - 1))
    Refresh-Panel; Update-Status
}

$btnBack.Add_Click({ if ($script:ReviewIndex -gt 0) { Load-Position ($script:ReviewIndex - 1) } })
$btnForward.Add_Click({ if ($script:ReviewIndex -lt ($script:MoveHistory.Count - 1)) { Load-Position ($script:ReviewIndex + 1) } })

$form.Add_KeyDown({
    if ($args[1].KeyCode -eq 'Left')  { $btnBack.PerformClick() }
    if ($args[1].KeyCode -eq 'Right') { $btnForward.PerformClick() }
})

function Get-AlgebraicMoveText([TinyCsChess.Board]$before, [TinyCsChess.Board]$after) {
    $from = -1
    $to   = -1
    for ($i = 0; $i -lt 64; $i++) {
        $a = $after.S[$i]
        $b = $before.S[$i]
        if ($b -ne '.' -and $a -eq '.') { $from = $i }
        elseif ($b -eq '.' -and $a -ne '.') { $to = $i }
    }
    if ($from -lt 0 -or $to -lt 0) { return "ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦" }

    $files = "abcdefgh"
    $ranks = "12345678"
    $fromText = "{0}{1}" -f $files[[TinyCsChess.Board]::FileOf($from)], $ranks[[TinyCsChess.Board]::RankOf($from)]
    $toText   = "{0}{1}" -f $files[[TinyCsChess.Board]::FileOf($to)],   $ranks[[TinyCsChess.Board]::RankOf($to)]
    $piece = $before.S[$from]
    $isPawn = ($piece -eq 'P' -or $piece -eq 'p')
    $prefix = if ($isPawn) { "" } else { [string]([char]([char]::ToUpper($piece))) }
    return "$prefix$fromText-$toText"
}


# --- Passive recorder (only logs new real moves) ---
$histTimer = New-Object System.Windows.Forms.Timer
$histTimer.Interval = 120
$histTimer.Add_Tick({
    try {
        $h = $board.ComputeHash()
        if ($script:LastHash -eq $null) {
            $script:LastHash = $h
            $script:LastBoard = $board.Copy()
            return
        }

        # only record when board actually changed and user is at newest position
        if ($h -ne $script:LastHash -and $script:ReviewIndex -eq ($script:MoveHistory.Count - 1)) {
            $text = Get-AlgebraicMoveText $script:LastBoard $board
            $script:LastBoard = $board.Copy()
            $script:LastHash = $h
            Record-PositionFromBoard
            $listHistory.Items[$listHistory.Items.Count - 1] = $text
        }
    } catch {}
})

# --- Initialize and start ---
$form.Add_Shown({
    if ($script:MoveHistory.Count -eq 0) {
        Record-PositionFromBoard
        $script:LastHash = $board.ComputeHash()
        $script:LastBoard = $board.Copy()
        $listHistory.Items[0] = "Start"
    }
    $histTimer.Start()
    Adjust-FormSize
})




$form.Controls.AddRange(@($lblSide,$sideCombo,$btnNew,$lblStatus,$panel))

# Orientation
$script:HumanIsWhite = $true

# Drag state
$script:Dragging   = $false
$script:DragFrom   = -1
$script:DragPiece  = [char]0
$script:DragPoint  = New-Object Drawing.Point -ArgumentList 0, 0
$script:LegalTos   = @()

# ===== Sprite support (Wikipedia)  crisp, pre-sized to $tile =====
$script:SpritesOk   = $false
$script:SpriteSheet = $null
$script:PieceBmp    = @{}  # char -> System.Drawing.Bitmap ($tile x $tile)

function Initialize-Sprites {
    param([int]$TileSize)

    $desiredWidth = [Math]::Max(6*[int]$TileSize, 270)
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

        # NOTE: Centaur sprites are no longer loaded here.
        $script:PieceBmp[[char]'.'] = $null
        $script:SpritesOk = $true
    }
    catch {
        $script:SpritesOk = $false
        if($script:SpriteSheet){ $script:SpriteSheet.Dispose(); $script:SpriteSheet = $null }
        # fallback handled in DrawPiece
    }
}

# Lazy init for Centaur sprites, only when Centaur variant is active
$script:CentaurSpritesReady = $false
$script:CentaurSpritesTile  = $null
function Ensure-CentaurSprites {
    param([int]$TileSize)

    if (-not $TileSize) {
        $TileSize = $tile  # fall back to global tile size
    }

    if ($script:CentaurSpritesReady -and $script:CentaurSpritesTile -eq $TileSize) { return }

    try {
        Write-Host "Loading centaur sprites at tilesize $TileSize..." -ForegroundColor Cyan

        # NOTE: use [char] keys to match Initialize-Sprites + DrawPiece
        $script:PieceBmp[[char]'C'] = [TinyCsChess.Engine+SpriteHelper]::LoadBitmapFromUrl(
            "https://greenchess.net/piece/white-centaur.png"
        )
        $script:PieceBmp[[char]'c'] = [TinyCsChess.Engine+SpriteHelper]::LoadBitmapFromUrl(
            "https://greenchess.net/piece/black-centaur.png"
        )

        foreach ($sym in 'C','c') {
            $key = [char]$sym
            $bmp = $script:PieceBmp[$key]
            if ($bmp -and ($bmp.Width -ne $TileSize -or $bmp.Height -ne $TileSize)) {
                $scaled = New-Object Drawing.Bitmap $TileSize, $TileSize
                $g = [Drawing.Graphics]::FromImage($scaled)
                $g.CompositingQuality = 'HighQuality'
                $g.InterpolationMode  = 'HighQualityBicubic'
                $g.PixelOffsetMode    = 'HighQuality'
                $g.SmoothingMode      = 'HighQuality'
                $g.DrawImage($bmp, 0, 0, $TileSize, $TileSize)
                $g.Dispose()
                $bmp.Dispose()
                $script:PieceBmp[$key] = $scaled
            }
        }

        $script:CentaurSpritesReady = $true
        $script:CentaurSpritesTile  = $TileSize
        Write-Host "Centaur sprites loaded and scaled." -ForegroundColor Green
    }
    catch {
        Write-Warning "Centaur sprite load failed — using glyph fallback. $($_.Exception.Message)"
        $script:CentaurSpritesReady = $false
        $script:CentaurSpritesTile  = $null
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
    if($script:FlippedView -xor (-not $script:HumanIsWhite)){
        return (7-$vr)*8 + (7-$vf)
    } else {
        return $vr*8 + $vf
    }

}

function DrawPiece($g, [char]$piece, [int]$cx, [int]$cy){
    if ($piece -eq '.') { return }

    # Optional lazy init, but not strictly required if Sync-Variant already called it
    if (($piece -eq 'C' -or $piece -eq 'c') -and -not $script:PieceBmp.ContainsKey($piece)) {
        try { Ensure-CentaurSprites -TileSize $tile } catch {}
    }

    if ($script:PieceBmp.ContainsKey($piece) -and $script:PieceBmp[$piece]) {
        $bmp = $script:PieceBmp[$piece]
        $x = $cx - [int]($bmp.Width / 2)
        $y = $cy - [int]($bmp.Height / 2)
        $g.DrawImage($bmp, $x, $y, $bmp.Width, $bmp.Height)
    }
    else {
        if ($glyph.ContainsKey([char]$piece)) {
            $g.DrawString($glyph[[char]$piece], $font, [Drawing.Brushes]::Black, $cx, $cy, $sf)
        } else {
            $g.DrawString("?", $font, [Drawing.Brushes]::Red, $cx, $cy, $sf)
        }
    }
}



function Draw-Board([object]$s,[object]$e){
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $g.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceOver  
    $g.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
    for($vr=0; $vr -lt 8; $vr++){
        for($vf=0; $vf -lt 8; $vf++){
            $x=$vf*$tile; $y=(7-$vr)*$tile
            if((($vr+$vf)%2) -eq 1){
                $g.FillRectangle($lightBrush, $x, $y, $tile, $tile)
            } else {
                $g.FillRectangle($darkBrush, $x, $y, $tile, $tile)
            }

            # model square for this view
            $msq = if($script:FlippedView -xor (-not $script:HumanIsWhite)){
                (7-$vr)*8 + (7-$vf)
            } else {
                $vr*8 + $vf
            }


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
    Sync-Variant
    $board.Reset()
    $script:HumanIsWhite = ($sideCombo.SelectedIndex -eq 0)
    $script:Dragging=$false; $script:DragFrom=-1; $script:DragPiece=[char]0; $script:LegalTos=@()
    Refresh-Panel; Update-Status
    if(-not $script:HumanIsWhite){

        [TinyCsChess.Globals]::VariantGiveaway = ($script:Variant -eq "Giveaway")

        # Computer (White) makes the first move synchronously
        $best = $engine.GetBestMove($board)
        if ($best -and $best.From -ne -1) {
            $board.MakeMove($best)
        }

        Refresh-Panel; Update-Status
    }
}

$form.Add_Shown({
    Initialize-Sprites -TileSize $tile
    Sync-Variant
    Start-NewGame
})

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
            if($script:Variant -eq "Horde"){
                # White wins when black king is checkmated
                if(-not ($board.S -contains 'P' -or $board.S -contains 'N' -or $board.S -contains 'B' -or $board.S -contains 'R' -or $board.S -contains 'Q' -or $board.S -contains 'K')){
                    [Windows.Forms.MessageBox]::Show("Horde win! The horde has overrun the king.") | Out-Null
                } else {
                    [Windows.Forms.MessageBox]::Show("Checkmate! The horde has been defeated.") | Out-Null
                }
                Start-NewGame; return
            }
            if($script:Variant -eq "Giveaway"){
                [Windows.Forms.MessageBox]::Show("Giveaway win! Side to move has no legal moves (stalemate) or lost all pieces.") | Out-Null

            } else {
                if($board.IsInCheck($board.WhiteToMove)){
                    [Windows.Forms.MessageBox]::Show("Checkmate! " + ($(if($board.WhiteToMove){"Computer"}else{"You"})) + " win(s).") | Out-Null
                } else {
                    [Windows.Forms.MessageBox]::Show("Stalemate.") | Out-Null
                }
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
