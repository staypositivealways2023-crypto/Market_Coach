import '../models/analysis_highlight.dart';
import '../models/lesson.dart';
import '../models/market_index.dart';
import '../models/news_item.dart';
import '../models/stock_summary.dart';

const mockWatchlist = [
  StockSummary(
    ticker: 'AAPL',
    name: 'Apple Inc.',
    price: 187.97,
    changePercent: 0.60,
    sector: 'Technology',
    industry: 'Consumer Electronics',
    fundamentals: {
      'Market Cap': '\$2.95T',
      'P/E Ratio': '31.5',
      'Div Yield': '0.50%',
      '52W Range': '\$164 - \$199',
    },
    technicalHighlights: [
      'Price above 50 & 200-day averages with rising volume',
      'RSI holding mid-50s: steady momentum, not overbought',
      'Higher lows since last earnings: buyers stepping in',
    ],
  ),
  StockSummary(
    ticker: 'MSFT',
    name: 'Microsoft Corp.',
    price: 415.32,
    changePercent: 0.82,
    sector: 'Technology',
    industry: 'Software',
    fundamentals: {
      'Market Cap': '\$3.09T',
      'P/E Ratio': '36.2',
      'Div Yield': '0.72%',
      '52W Range': '\$362 - \$468',
    },
    technicalHighlights: [
      'Trading above all major moving averages — strong uptrend',
      'AI/cloud segment driving revenue growth',
      'Key support at \$400; breakout above \$468 targets \$500',
    ],
  ),
  StockSummary(
    ticker: 'NVDA',
    name: 'NVIDIA Corp.',
    price: 875.48,
    changePercent: 1.43,
    sector: 'Technology',
    industry: 'Semiconductors',
    fundamentals: {
      'Market Cap': '\$2.16T',
      'P/E Ratio': '68.4',
      'Div Yield': '0.03%',
      '52W Range': '\$460 - \$974',
    },
    technicalHighlights: [
      'AI demand driving record earnings and revenue growth',
      'RSI elevated but consolidating after parabolic run',
      'Watch \$800 support; data centre backlog remains strong',
    ],
  ),
  StockSummary(
    ticker: 'GOOGL',
    name: 'Alphabet Inc.',
    price: 172.65,
    changePercent: 0.35,
    sector: 'Technology',
    industry: 'Internet Services',
    fundamentals: {
      'Market Cap': '\$2.18T',
      'P/E Ratio': '25.8',
      'Div Yield': '0.46%',
      '52W Range': '\$140 - \$208',
    },
    technicalHighlights: [
      'Consolidating after pullback from highs',
      'AI integration in Search & Cloud accelerating',
      'Support at \$165; break above \$180 resuming uptrend',
    ],
  ),
  StockSummary(
    ticker: 'TSLA',
    name: 'Tesla Inc.',
    price: 248.42,
    changePercent: -1.12,
    sector: 'Consumer Cyclical',
    industry: 'Electric Vehicles',
    fundamentals: {
      'Market Cap': '\$792B',
      'P/E Ratio': '78.6',
      'Div Yield': '—',
      '52W Range': '\$139 - \$480',
    },
    technicalHighlights: [
      'High volatility — wide swings tied to delivery reports',
      'Trading well below 52-week highs; broken downtrend',
      'Key level: \$250 resistance; support at \$220',
    ],
  ),
  StockSummary(
    ticker: 'AMZN',
    name: 'Amazon.com Inc.',
    price: 196.87,
    changePercent: 0.54,
    sector: 'Consumer Cyclical',
    industry: 'E-Commerce & Cloud',
    fundamentals: {
      'Market Cap': '\$2.09T',
      'P/E Ratio': '44.1',
      'Div Yield': '—',
      '52W Range': '\$161 - \$230',
    },
    technicalHighlights: [
      'AWS growth re-accelerating; margin expansion on track',
      'Pullback from highs providing re-entry zone',
      'Support at \$190; prior highs at \$230 are target',
    ],
  ),
  StockSummary(
    ticker: 'BHP',
    name: 'BHP Group',
    price: 45.84,
    changePercent: -0.49,
    sector: 'Materials',
    industry: 'Diversified Mining',
    fundamentals: {
      'Market Cap': '\$233B',
      'P/E Ratio': '12.4',
      'Div Yield': '6.10%',
      '52W Range': '\$42 - \$51',
    },
    technicalHighlights: [
      'Trading near support with falling volume on pullbacks',
      'MACD turning up: early momentum shift',
      'Range-bound; breakout above \$48 would confirm strength',
    ],
  ),
  StockSummary(
    ticker: 'BTC',
    name: 'Bitcoin',
    price: 42148.47,
    changePercent: -0.39,
    isCrypto: true,
    sector: 'Digital Asset',
    industry: 'Settlement Layer',
    fundamentals: {
      'Market Cap': '\$825B',
      'Dominance': '52.1%',
      'Circulating Supply': '19.5M BTC',
      'Realized Vol (30d)': '38%',
    },
    technicalHighlights: [
      'Holding above 200-day; pullbacks bought quickly',
      'Funding rates neutral: no extreme leverage',
      'Watching 40k support / 46k resistance range',
    ],
  ),
  StockSummary(
    ticker: 'ETH',
    name: 'Ethereum',
    price: 2451.72,
    changePercent: 1.24,
    isCrypto: true,
    sector: 'Digital Asset',
    industry: 'Smart Contract Platform',
    fundamentals: {
      'Market Cap': '\$295B',
      'Dominance': '18.6%',
      'Circulating Supply': '120.2M ETH',
      'Realized Vol (30d)': '42%',
    },
    technicalHighlights: [
      'Strong support at \$2400 after breaking out',
      'Network activity increasing with L2 growth',
      'Watching 2550 resistance for continuation',
    ],
  ),
  StockSummary(
    ticker: 'ADA',
    name: 'Cardano',
    price: 0.58,
    changePercent: 2.15,
    isCrypto: true,
    sector: 'Digital Asset',
    industry: 'Smart Contract Platform',
    fundamentals: {
      'Market Cap': '\$20.5B',
      'Dominance': '1.3%',
      'Circulating Supply': '35.3B ADA',
      'Realized Vol (30d)': '48%',
    },
    technicalHighlights: [
      'Breaking above 50-day MA with increasing volume',
      'Development activity remains strong',
      'Key resistance at \$0.65 from previous highs',
    ],
  ),
  StockSummary(
    ticker: 'XRP',
    name: 'Ripple',
    price: 0.52,
    changePercent: -1.34,
    isCrypto: true,
    sector: 'Digital Asset',
    industry: 'Payment Protocol',
    fundamentals: {
      'Market Cap': '\$28.7B',
      'Dominance': '1.8%',
      'Circulating Supply': '55.2B XRP',
      'Realized Vol (30d)': '51%',
    },
    technicalHighlights: [
      'Consolidating in tight range after recent rally',
      'Legal clarity driving institutional interest',
      'Support at \$0.48, resistance at \$0.58',
    ],
  ),
  StockSummary(
    ticker: 'XLM',
    name: 'Stellar',
    price: 0.11,
    changePercent: 0.87,
    isCrypto: true,
    sector: 'Digital Asset',
    industry: 'Payment Protocol',
    fundamentals: {
      'Market Cap': '\$3.1B',
      'Dominance': '0.2%',
      'Circulating Supply': '28.5B XLM',
      'Realized Vol (30d)': '54%',
    },
    technicalHighlights: [
      'Following Bitcoin correlation closely',
      'Partnership announcements supporting price',
      'Range-bound between \$0.10 and \$0.13',
    ],
  ),
];

final mockLessons = [
  Lesson(
    id: 'lesson_pe_ratio',
    title: 'Price to Earnings (P/E) explained',
    subtitle: 'A quick way to tell if a stock looks pricey or cheap',
    minutes: 3,
    level: 'Beginner',
    body:
        'The P/E ratio compares a company’s price to the money it earns each year. '
        'If a stock has a P/E of 20, investors are paying \$20 for every \$1 of yearly profit.\n\n'
        'Simple picture: imagine buying a lemonade stand. If it makes \$1 a year and you pay \$20, '
        'it would take about 20 years to earn your money back. That is a P/E of 20.\n\n'
        'High P/E: investors expect bigger growth later. Low P/E: investors expect slower growth or see higher risk.\n\n'
        'Example: AAPL at \$187 with earnings per share of \$5.93 → P/E ≈ 31.5. Compare with peers before judging.',
  ),
  Lesson(
    id: 'lesson_support_resistance',
    title: 'Support & resistance with pictures',
    subtitle: 'Why prices often bounce at familiar zones',
    minutes: 4,
    level: 'Beginner',
    body:
        'Support is a price “floor” where buyers tend to step in. Resistance is a “ceiling” where sellers often take profits.\n\n'
        'Think of price as a ball on stairs: each step can act as support when falling and resistance when rising.\n\n'
        'Figure example: price falls to \$100 three times and bounces — that \$100 zone is support. '
        'If price later breaks above \$110 and holds, \$110 can become the new support.\n\n'
        'Tip: Draw zones, not single lines. Look for clusters of past highs/lows and volume.',
  ),
  Lesson(
    id: 'lesson_volatility',
    title: 'Volatility made simple',
    subtitle: 'How “bumpy” a ride to expect before you buy',
    minutes: 3,
    level: 'Beginner',
    body:
        'Volatility measures how fast and how far prices swing. Higher volatility means bigger jumps; lower means steadier moves.\n\n'
        'Plain language: A calm stock might move \$0.50 a day; a volatile crypto could move \$500 a day.\n\n'
        'Figure example: Two lines start at \$100. One zigzags between \$95-105 (low volatility). '
        'The other jumps between \$80-120 (high volatility).\n\n'
        'Use case: Size smaller in high volatility to avoid large dollar swings.',
  ),
  Lesson(
    id: 'lesson_position_sizing',
    title: 'Position sizing with a safety buffer',
    subtitle: 'Keep losses small so you can keep playing',
    minutes: 4,
    level: 'Intermediate',
    body:
        'Position sizing is deciding how much to put into one idea. Many investors risk only 0.5%–2% of their account on a trade.\n\n'
        'Example: \$10,000 account, willing to risk 1% (\$100). If your stop is \$2 below entry, you can buy \$100 / 2 = 50 shares.\n\n'
        'Figure: Account bar showing 98–99% protected, 1–2% at risk per trade.\n\n'
        'Small, consistent risk keeps losing streaks survivable and emotions calmer.',
  ),
  Lesson(
    id: 'lesson_stops',
    title: 'Stops that respect the idea',
    subtitle: 'Place exits beyond normal noise',
    minutes: 5,
    level: 'Intermediate',
    body:
        'A good stop goes where your idea would be wrong, not just a random percent.\n\n'
        'Techniques: below recent swing low, under support, or using Average True Range (ATR) as a buffer.\n\n'
        'Example: If support is \$50 and ATR is \$1, a stop at \$48.80 leaves space for noise while protecting you.\n\n'
        'Figure: price bouncing near support with a shaded “noise” zone and a stop under it.',
  ),
  Lesson(
    id: 'lesson_catalysts',
    title: 'Macro vs micro catalysts',
    subtitle: 'What can move prices this week',
    minutes: 5,
    level: 'Intermediate',
    body:
        'Macro catalysts: central bank decisions, inflation (CPI), jobs data, geopolitics. '
        'They move whole markets.\n\n'
        'Micro catalysts: earnings, product launches, guidance updates, insider activity. '
        'They move single stocks.\n\n'
        'Example: Even if a company beats earnings, a surprise rate hike can drag the stock down. '
        'Always check the macro calendar before trading a micro story.',
  ),
];

const mockIndices = [
  MarketIndex(
    name: 'S&P 500',
    ticker: 'SPX',
    value: 5189.3,
    changePercent: 0.42,
  ),
  MarketIndex(
    name: 'NASDAQ 100',
    ticker: 'NDX',
    value: 18234.1,
    changePercent: 0.65,
  ),
  MarketIndex(
    name: 'Dow Jones',
    ticker: 'DJI',
    value: 39682.7,
    changePercent: 0.18,
  ),
  MarketIndex(name: 'VIX', ticker: 'VIX', value: 13.8, changePercent: -3.4),
];

const mockCryptoIndices = [
  MarketIndex(
    name: 'Bitcoin',
    ticker: 'BTC',
    value: 42148.47,
    changePercent: -0.39,
  ),
  MarketIndex(
    name: 'Ethereum',
    ticker: 'ETH',
    value: 2451.72,
    changePercent: 1.24,
  ),
  MarketIndex(
    name: 'Solana',
    ticker: 'SOL',
    value: 102.41,
    changePercent: -2.1,
  ),
  MarketIndex(
    name: 'Cardano',
    ticker: 'ADA',
    value: 0.58,
    changePercent: 2.15,
  ),
  MarketIndex(
    name: 'Ripple',
    ticker: 'XRP',
    value: 0.52,
    changePercent: -1.34,
  ),
  MarketIndex(
    name: 'Stellar',
    ticker: 'XLM',
    value: 0.11,
    changePercent: 0.87,
  ),
];

const mockNews = [
  NewsItem(
    title: 'Mega-cap tech lifts indices while yields ease',
    source: 'Bloomberg',
    timeAgo: '8m ago',
    summary:
        'Big tech leads a broad rally as bond yields drift lower after cooler inflation data. '
        'Traders price higher odds of a rate cut this quarter.',
    sentiment: 'Bullish',
  ),
  NewsItem(
    title: 'Crude slips on demand worries after mixed inventory data',
    source: 'Reuters',
    timeAgo: '32m ago',
    summary:
        'Weekly inventories surprised to the upside, offsetting ongoing supply risks. '
        'Energy names lag the broader market.',
    sentiment: 'Bearish',
  ),
  NewsItem(
    title: 'Semis stay hot as AI orders accelerate',
    source: 'The Verge',
    timeAgo: '1h ago',
    summary:
        'Chipmakers cite strong backlog tied to AI buildouts, keeping margins elevated. '
        'Valuations remain a debate.',
    sentiment: 'Bullish',
  ),
  NewsItem(
    title: 'Retail sales cool, but services stay resilient',
    source: 'WSJ',
    timeAgo: '2h ago',
    summary:
        'Consumers shift spending from goods to experiences; economists see slower but still positive GDP prints.',
    sentiment: 'Neutral',
  ),
];

const mockAnalysis = [
  AnalysisHighlight(
    title: 'Apple momentum stays intact',
    subtitle: 'Higher highs with rising volume',
    tag: 'Technical',
    confidence: 0.78,
    body:
        'AAPL holds above its 50-day with constructive pullbacks. Break above 190 keeps 200 in play if volume confirms.',
  ),
  AnalysisHighlight(
    title: 'Banks rerate on lower-for-longer yields',
    subtitle: 'NIM pressure, but credit quality steady',
    tag: 'Fundamental',
    confidence: 0.61,
    body:
        'If the Fed eases sooner, net interest margins compress but loan growth could re-accelerate. Watch credit provisions and fee income.',
  ),
  AnalysisHighlight(
    title: 'Energy dips present a swing window',
    subtitle: 'Supply risk vs soft demand',
    tag: 'Macro',
    confidence: 0.54,
    body:
        'Pullbacks toward 100-day MAs in integrated names look buyable if crude stays above 70. A sharp demand downtick would break the thesis.',
  ),
  AnalysisHighlight(
    title: 'Small caps need earnings follow-through',
    subtitle: 'Breadth improving, but margins thin',
    tag: 'Breadth',
    confidence: 0.57,
    body:
        'Russell 2000 participation is ticking up, yet operating leverage is limited. Prefer quality screens and lower leverage.',
  ),
];
