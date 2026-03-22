"""Mock Analysis Service - Pre-generated sample analyses for testing"""

from typing import Dict
import logging

logger = logging.getLogger(__name__)


class MockAnalysisService:
    """Provides pre-generated mock analyses for testing without API calls"""

    # Pre-generated sample analyses
    MOCK_ANALYSES = {
        "AAPL": """## Market Context

Apple (AAPL) is currently trading with strong momentum, showing classic signs of a well-established uptrend. The price action suggests investor confidence remains high, though we're seeing some signs that warrant attention.

## Technical Analysis

The **RSI at 68** is approaching overbought territory - think of it like a pressure gauge on a tire getting close to the red zone. It's not overinflated yet, but it's something to watch. This tells us buying pressure has been strong, but might be reaching a temporary peak.

The **MACD histogram is positive and expanding**, which is like seeing the gap widen between two runners - the faster one (recent prices) is pulling ahead of the slower one (longer-term average). This confirms the upward momentum is real and strengthening.

**Price is riding above all major moving averages** (20, 50, and 200-day). This is significant! Think of moving averages like support levels - the fact that price is comfortably above all three is like a climber standing on solid ground at each level. It shows the trend has multiple layers of support.

**Bollinger Bands** show price near the upper band, indicating strong upward pressure. The bands are widening, which suggests volatility is increasing - markets are getting more "excited" about this move.

## Fundamental Perspective

The **DCF valuation suggests intrinsic value around $172** versus the current price near $185. This 7% premium tells us the market is paying a bit more than pure fundamentals suggest - but that's not unusual for a quality company with strong momentum.

**P/E ratio of 29** is elevated compared to the broader market, but Apple has earned this premium through consistent execution. With **ROE over 140%**, the company is exceptionally efficient at turning shareholder capital into profits - one of the best in the industry.

**Revenue growth of 8%** combined with **profit margins of 26%** shows this isn't a growth-at-all-costs story - Apple is growing sustainably while maintaining industry-leading profitability.

## Key Considerations

Here's where it gets interesting: we have a **conflict between technicals and fundamentals**. The technicals are screaming strength (price trends, momentum), but fundamentals suggest slight overvaluation. This teaches us an important lesson: **momentum can override valuation in the short term**.

Markets don't always care about "fair value" day-to-day. Sometimes the story, sentiment, and technical setup matter more. But longer-term, fundamentals tend to reassert themselves.

The approaching overbought RSI combined with the valuation premium suggests this might not be the ideal entry point for new positions. However, the strong trend and multiple support levels suggest the uptrend isn't ready to end just yet.

## Learning Opportunities

This is a perfect case study for understanding the relationship between **technical momentum** and **fundamental valuation**.

Want to learn more? Check out these lessons:
- **"RSI Mastery"** - Understanding overbought/oversold conditions
- **"Moving Averages as Support"** - How trends build on layers of support
- **"DCF Valuation Fundamentals"** - Calculating intrinsic value
- **"When Technicals and Fundamentals Disagree"** - Navigating mixed signals

Remember: The goal isn't to predict what will happen next, but to understand the forces at play so you can make informed decisions aligned with your strategy and risk tolerance.
""",

        "TSLA": """## Market Context

Tesla is showing its characteristic volatility, with price action that reflects the market's ongoing debate about the company's valuation. We're seeing a tug-of-war between growth believers and valuation skeptics.

## Technical Analysis

**RSI at 55** sits right in the neutral zone - like a pendulum at rest. This suggests neither buyers nor sellers have decisive control right now. After recent swings, this equilibrium might be a pause before the next move.

The **MACD shows a bullish crossover forming**, where the MACD line is crossing above the signal line. Think of this like two trains on parallel tracks - when the faster train (MACD) crosses in front of the slower one (signal), it often indicates a shift in momentum direction.

**Price is above the 20 and 50-day moving averages but below the 200-day**. This mixed picture is like standing on the second floor of a building - you've climbed above the lower levels (short-term support), but you're still below the roof (long-term trend). The 200-day MA is acting as overhead resistance.

**Bollinger Bands are contracting**, which suggests volatility is compressing. This is like a spring being wound tight - often, periods of low volatility are followed by explosive moves in either direction.

## Fundamental Perspective

Here's where Tesla gets interesting from a valuation standpoint. With a **P/E ratio of 45**, the market is pricing in significant future growth. This is like paying for a tree based on the fruit it might bear in 5 years, not what's on the branches today.

**Revenue growth of 18%** is solid, but the premium P/E suggests investors expect this to accelerate or sustain for years. The company's **profit margin of 15%** shows they're profitable, but automotive margins are under pressure from competition.

**ROE of 22%** is respectable, showing efficient capital use, though down from previous peaks as the company scales and competition intensifies.

The **PEG ratio of 2.3** is elevated - ideally, you want this below 1.0. This suggests the growth rate might not fully justify the current price multiple.

## Key Considerations

Tesla perfectly illustrates the difference between a **great company** and a **great stock at any price**. The company is revolutionizing the auto industry, but that doesn't automatically mean the current price offers attractive risk/reward.

The technical setup shows **consolidation after recent volatility** - price is digesting previous moves. The contracting Bollinger Bands warn us to be ready for a breakout in either direction.

**Fundamental vs. Technical conflict**: While the valuation is stretched (high P/E, high PEG), the technical setup shows resilience with price holding above short-term moving averages.

## Learning Opportunities

Tesla is an excellent case study for several key concepts:

- **"Growth Investing Fundamentals"** - When high valuations make sense (and when they don't)
- **"Volatility and Bollinger Bands"** - Reading compression and expansion patterns
- **"Support and Resistance"** - How moving averages act as decision points
- **"The PEG Ratio"** - Valuing growth at a reasonable price

The key lesson: Innovation and growth potential are valuable, but so is the price you pay. Understanding this balance is crucial for long-term success.
""",

        "BTC-USD": """## Market Context

Bitcoin is trading with characteristic volatility, displaying the price action of a maturing but still-evolving asset class. The current setup shows elements of both strength and caution.

## Technical Analysis

**RSI at 62** indicates solid buying pressure without being extended into overbought territory. Think of this like a car's tachometer - the engine is running strong but not redlining. There's still room for upward movement before reaching extreme levels.

The **MACD is bullish with positive histogram values**. The MACD line sits comfortably above the signal line, and the expanding histogram shows this bullish momentum is actually strengthening, not fading. This is like watching the distance grow between a leader and second place in a race.

**Price action above all major moving averages** is a significant technical strength. Bitcoin is trading above its 20-day (short-term sentiment), 50-day (intermediate trend), and 200-day (long-term trend) moving averages. This triple-layer support structure suggests the uptrend has depth and isn't just a short-term spike.

**Bollinger Bands show price in the upper half** of the range, with moderate width. This indicates steady upward pressure without the extreme volatility spikes we sometimes see in crypto. The measured pace might actually be healthier for sustainability.

**Volume patterns** (when available) show consistent participation, not just sporadic spikes - suggesting institutional interest rather than pure retail speculation.

## Fundamental Perspective

For Bitcoin, "fundamentals" look different than stocks. Instead of earnings and revenue, we analyze:

**Adoption Metrics**: Institutional holdings continue growing, with several major financial institutions now offering Bitcoin exposure to clients. This legitimization is a slow-burn positive catalyst.

**Network Activity**: On-chain metrics show steady transaction volume and active addresses, indicating the network is being used, not just speculated on.

**Regulatory Environment**: While regulations remain in flux globally, the trend is toward acceptance and framework creation rather than outright bans in major economies. This reduces existential risk.

**Supply Dynamics**: With the recent halving event, new Bitcoin issuance has decreased. Basic economics tells us that if demand stays constant or grows while new supply shrinks, price pressure trends upward.

**Macro Environment**: Bitcoin continues to establish itself as a potential inflation hedge and alternative store of value, though this narrative gets tested during market stress.

## Key Considerations

The **technical setup is constructive** - we have higher lows, higher highs, and strong trend structure. However, Bitcoin's volatility means even healthy uptrends can experience sharp 20-30% pullbacks without breaking the overall pattern.

**Lack of traditional fundamentals** means technical analysis carries extra weight for Bitcoin. Price action and trend structure become even more important when you can't fall back on P/E ratios or revenue growth.

**Correlation risk**: Bitcoin can still show sudden correlation with risk assets during market stress, despite the "digital gold" narrative. Don't assume complete independence from broader market moves.

The current setup suggests **"cautiously bullish"** - the trend is up, technicals are supportive, but the inherent volatility demands respect. Position sizing becomes crucial.

## Learning Opportunities

Bitcoin offers unique learning experiences:

- **"Technical Analysis Mastery"** - When price action is your primary guide
- **"Understanding Crypto Fundamentals"** - On-chain metrics, network effects, and adoption
- **"Volatility Management"** - Surviving and thriving in high-volatility assets
- **"Alternative Assets"** - Portfolio diversification beyond stocks and bonds
- **"Risk Management Essentials"** - Position sizing for volatile assets

Key takeaway: Bitcoin requires a different analytical framework than traditional assets. Embrace the technicals, understand the unique "fundamentals," and never underestimate the volatility. The asset class is maturing, but maturity is relative - expect continued wild swings even within strong uptrends.
""",

        "NVDA": """## Market Context

NVIDIA is trading in the spotlight as the AI revolution's primary hardware beneficiary. The stock reflects both the explosive growth story and the questions about sustainability at these valuations.

## Technical Analysis

**RSI at 74** is firmly in overbought territory - the pressure gauge is deep in the red zone. This doesn't mean the stock must fall immediately (strong trends can stay overbought for extended periods), but it signals that buying pressure has been extreme and a breather would be healthy.

The **MACD remains strongly bullish** despite the elevated RSI. The histogram is positive and the MACD line sits well above the signal line. This is like a car accelerating up a hill - it's going fast (overbought RSI) but the engine is still pushing hard (positive MACD).

**Price is extended well above all moving averages**. The 20-day MA sits 8% below current price, the 50-day is 15% below, and the 200-day is 30% below. This vertical separation is like a rocket that's achieved escape velocity - impressive, but also far from the ground. The gap becomes risk if momentum fades.

**Bollinger Bands are extremely wide** with price riding the upper band. Wide bands indicate high volatility, and riding the upper band shows relentless buying pressure. But like an elastic stretched too far, the wider the bands, the more energy is stored for a potential snapback.

## Fundamental Perspective

NVIDIA's fundamentals are genuinely extraordinary, which explains some of the premium:

**Revenue growth at 122%** - yes, you read that right. The AI boom has created explosive demand for their GPUs. This isn't incremental growth; it's transformational.

**Profit margins of 55%** show incredible pricing power. When you're the only game in town for essential AI infrastructure, you can command premium prices.

**P/E ratio of 52** seems high until you compare it to the growth rate. The **PEG ratio of 0.43** actually suggests the stock is *undervalued* relative to growth - a rare combination.

**ROE of 115%** demonstrates exceptional capital efficiency. The company is turning every dollar of equity into more than a dollar of profit annually.

However, **here's the catch**: These growth rates are unlikely to sustain indefinitely. Competition is coming, and the law of large numbers eventually applies to everyone.

## Key Considerations

We have a **fascinating contradiction**: Technical indicators scream "overbought" while fundamental growth rates seem to justify (or even support) higher valuations. This is a classic case of a **powerful narrative meeting stretched technicals**.

**The AI story is real**, but stories can be properly valued, overvalued, or undervalued at any given moment. Right now, the market is paying a premium for certainty that this growth continues.

**Risk of a momentum reversal**: When heavily extended stocks start to fade, the profit-taking can be swift. The 30% gap to the 200-day MA represents a long fall if sentiment shifts.

**Timing vs. Valuation**: Even if NVDA is "fairly valued" based on growth, that doesn't mean entering at technical extremes is wise. Great companies can be bad trades at the wrong price.

## Learning Opportunities

NVIDIA offers masterclass lessons in several areas:

- **"Growth at a Reasonable Price (GARP)"** - Balancing growth rates with valuation multiples
- **"Momentum Investing"** - Riding strong trends while managing risk of reversals
- **"Overbought Doesn't Mean Overvalued"** - Technical vs. fundamental perspectives
- **"Thematic Investing"** - Understanding how mega-trends create opportunities (and risks)
- **"Position Sizing in Extended Markets"** - Managing risk when everything seems expensive

The critical insight: NVIDIA might be both *correctly valued* on fundamentals and *dangerously extended* on technicals simultaneously. Your decision depends on your timeframe, risk tolerance, and whether you're trying to time entries or build long-term positions.

Sometimes the best trade is waiting for a better entry point in a great company.
""",

        "ETH-USD": """## Market Context

Ethereum is navigating the complex landscape of being both a technology platform and a financial asset. The current price action reflects the ongoing evolution from "world computer" concept to real-world utility.

## Technical Analysis

**RSI at 58** sits in healthy territory - neither overbought nor oversold. This neutral reading suggests the market is balanced between buyers and sellers, without either side showing exhaustion. Think of it as two equally matched teams in overtime - nobody has the upper hand yet.

The **MACD is showing early bullish signals**. The MACD line has recently crossed above the signal line, and the histogram is turning positive. This is like watching momentum shift from negative to positive - the rate of decline is slowing and potentially reversing to gains.

**Price is above the 50 and 200-day moving averages but choppy around the 20-day**. This suggests the longer-term trend remains intact (above the major MAs), but short-term direction is still being negotiated. It's like a hiker who's generally climbing a mountain but taking some back-and-forth paths near the current elevation.

**Bollinger Bands show moderate width** with price oscillating between the middle and upper band. This healthy volatility range suggests normal price discovery without extreme panic or euphoria.

**Volume** shows steady but unspectacular participation - institutional-level interest without the retail-driven spikes that often mark tops and bottoms.

## Fundamental Perspective

Ethereum's fundamentals differ from Bitcoin and require unique analysis:

**Network Utility**: Ethereum processes significant real economic activity - DeFi protocols, NFT marketplaces, and stablecoin transfers. This usage creates inherent demand for ETH (as "gas" for transactions), giving it a utility value beyond pure speculation.

**The Merge Success**: The transition to Proof-of-Stake reduced ETH issuance by ~90%. Combined with EIP-1559 (which burns a portion of transaction fees), Ethereum now has deflationary potential during high-usage periods. Less new supply + steady/growing demand = upward price pressure over time.

**Staking Dynamics**: With ~25% of ETH staked (locked up earning yield), there's significant supply removed from circulation. Staked ETH is like money in a time-locked savings account - it can't be sold impulsively during volatility.

**Layer 2 Growth**: Scaling solutions like Arbitrum, Optimism, and Polygon are processing millions of transactions at fraction-of-a-cent costs, proving the ecosystem can scale without abandoning Ethereum's security.

**Developer Activity**: Ethereum maintains the largest developer ecosystem in crypto, which historically correlates with long-term value. More builders = more applications = more users = more demand.

**Competition**: Solana, Avalanche, and others offer faster/cheaper transactions, creating ongoing pressure. Ethereum's bet is that security and decentralization matter more than speed - time will tell if users agree.

## Key Considerations

Ethereum faces an interesting **value proposition debate**: Is it a commodity (like oil for the crypto economy), a store of value (like digital silver to Bitcoin's gold), a productive asset (generating staking yields), or all three?

The **technical setup is constructive but not compelling** - we're in "wait and see" mode. Neither bulls nor bears have clear control, which often leads to choppy, range-bound trading until a catalyst emerges.

**Correlation with Bitcoin** remains high but not perfect. Ethereum sometimes lags Bitcoin rallies initially, then plays catch-up. Understanding this relationship helps with entry/exit timing.

**Regulatory uncertainty** remains a wildcard. The SEC's position on whether ETH is a security or commodity could significantly impact institutional adoption.

## Learning Opportunities

Ethereum is an excellent study in:

- **"Layer 1 Blockchain Economics"** - Understanding tokenomics beyond simple supply/demand
- **"Staking and Yield Generation"** - How crypto enables passive income
- **"Network Effects in Crypto"** - Why the biggest ecosystem often stays the biggest
- **"Reading Range-Bound Markets"** - Trading chop vs. trending moves
- **"Crypto Correlations"** - How different assets move relative to each other

The key insight: Ethereum sits at the intersection of technology and finance. Understanding both the technical (blockchain capabilities) and fundamental (economic design) aspects gives you an edge. The current neutral technical setup suggests patience - let the pattern develop before committing strongly in either direction.

Sometimes the best position is "wait for clarity."
""",

        "SPY": """## Market Context

The S&P 500 (via SPY) is trading near all-time highs, reflecting a market that's digested the previous year's volatility and found renewed confidence. But beneath the calm surface, there are undercurrents worth understanding.

## Technical Analysis

**RSI at 64** shows solid upward momentum without reaching overbought extremes. This is a healthy reading for an uptrend - the engine is running strong but not overheating. There's room for further gains without triggering automatic technical selling.

The **MACD is firmly bullish** with both the MACD line and signal line in positive territory and the histogram expanding. This confirms the uptrend has underlying momentum, not just price grinding higher on low conviction.

**Price is above all major moving averages**, with particularly strong spacing above the 200-day MA. This triple-layer support structure shows the bull market has depth. Think of it like a building with a solid foundation, first floor, and second floor all intact - there's support at multiple levels if price retreats.

The **moving averages themselves are "stacked" correctly** for an uptrend - the 20-day above the 50-day, which is above the 200-day. This alignment is like three racehorses running in formation with the leader (short-term) in front, exactly as you want to see in healthy uptrends.

**Bollinger Bands show moderate width** with price in the upper half, indicating controlled volatility with upward bias. The market is rising steadily without the wild swings that often mark unsustainable moves.

**Volume** has been steady with occasional spikes on strong up days - a positive sign that institutional money is participating, not just retail speculation.

## Fundamental Perspective

The S&P 500's fundamentals are a weighted average of 500 companies, giving us a macro view:

**P/E ratio around 22** is historically elevated but not extreme. We're paying a premium relative to historical averages (typically 15-16), but well below the bubble levels of 2000 (30+). This suggests optimism with some justification.

**Earnings growth estimates of 11%** for the next year provide fundamental support for current valuations. If companies deliver on these expectations, the market multiple could even compress while prices hold or rise.

**Profit margins remain near record highs** at 12-13% for the index. This represents peak efficiency, which means there's more risk of margin compression than expansion from here.

**Interest rate environment**: With rates still elevated by recent standards, the competition for investor dollars is real. Bonds yielding 4-5% make stocks work harder to justify their valuations.

**Economic indicators** show resilience (low unemployment, consumer spending) but also caution (slowing manufacturing, inverted yield curve signals in recent past).

## Key Considerations

The **technical picture is uniformly positive** - trend, momentum, and structure all aligned bullishly. However, technical strength doesn't exist in a vacuum.

**Concentration risk**: Much of the S&P 500's performance is driven by the "Magnificent 7" tech stocks. When few stocks carry the index, it's like a table with only one leg - less stable than broad-based rallies.

**Valuation vs. opportunity cost**: At 22x earnings with bonds yielding 4.5%, stocks need to deliver meaningful growth to justify the risk premium. The margin for disappointment is slim.

**Seasonality**: Understanding where we are in the seasonal/election cycles can provide context, though never certainty.

The **lack of fear** in the market (VIX at low levels) can be both positive (nothing stopping the rally) and concerning (complacency before corrections).

## Learning Opportunities

SPY is perfect for learning broader market concepts:

- **"Index Investing Fundamentals"** - Why the S&P 500 is the market's benchmark
- **"Market Breadth Analysis"** - When few stocks lead vs. broad participation
- **"Valuation Cycles"** - Historical P/E ranges and what they mean
- **"Interest Rates and Stocks"** - The inverse relationship explained
- **"Market Sentiment Indicators"** - VIX, put/call ratios, and fear/greed measures
- **"Diversification Principles"** - Why the S&P 500 is "concentrated diversification"

The key insight: The S&P 500 is remarkably resilient over long timeframes but subject to sharp pullbacks in the short term. Current technicals suggest the path of least resistance is higher, but elevated valuations mean you're paying full price for this ticket. The question isn't "is the market good?" but "is the risk/reward compelling at these prices for your situation?"

Long-term investors might dollar-cost-average regardless. Tactical traders might wait for better entry points. Both approaches can be "right" depending on timeframe and goals.
"""
    }

    def generate_mock_analysis(self, symbol: str) -> Dict[str, any]:
        """
        Generate mock analysis for a symbol

        Args:
            symbol: Stock ticker symbol

        Returns:
            Dict with 'analysis_text' and 'tokens_used'
        """

        symbol = symbol.upper()

        # Use symbol-specific analysis if available, otherwise use a generic template
        if symbol in self.MOCK_ANALYSES:
            analysis_text = self.MOCK_ANALYSES[symbol]
            logger.info(f"Using custom mock analysis for {symbol}")
        else:
            # Generic template for unlisted symbols
            analysis_text = self._generate_generic_analysis(symbol)
            logger.info(f"Using generic mock analysis for {symbol}")

        # Mock token count (realistic range)
        tokens_used = len(analysis_text.split()) * 1.3  # Rough estimate

        return {
            "analysis_text": analysis_text,
            "tokens_used": int(tokens_used)
        }

    def _generate_generic_analysis(self, symbol: str) -> str:
        """Generate a generic analysis template for unsupported symbols"""

        return f"""## Market Context

{symbol} is currently being analyzed. This is a demonstration of the AI-powered analysis feature using mock data.

## Technical Analysis

The technical indicators for {symbol} show a mix of signals that require careful interpretation. The RSI and MACD are providing insights into momentum, while moving averages help establish trend context.

When analyzing any asset, it's crucial to look beyond individual indicators and understand how they interact to tell a complete story.

## Fundamental Perspective

For a complete fundamental analysis of {symbol}, we would examine:
- Valuation metrics (P/E, P/B, PEG ratios)
- Growth indicators (revenue and earnings growth)
- Profitability measures (margins, ROE, ROA)
- Balance sheet health (debt levels, current ratio)

Each of these provides a different lens for understanding intrinsic value.

## Key Considerations

Every investment involves trade-offs and risks. Understanding what you're buying, why you're buying it, and what could go wrong is essential for long-term success.

Market prices reflect collective opinions, which can differ from fundamental values in the short term. Your edge comes from patience, discipline, and a well-reasoned strategy.

## Learning Opportunities

This is a great opportunity to explore:
- **"Technical Analysis Fundamentals"** - Reading price charts and indicators
- **"Fundamental Analysis Basics"** - Valuing companies and assets
- **"Risk Management"** - Protecting your capital
- **"Building a Strategy"** - Aligning analysis with your goals

Remember: The goal of analysis is to make informed decisions, not perfect predictions. Markets are uncertain by nature, but thoughtful analysis reduces that uncertainty.

---

*This is a mock analysis for demonstration purposes. For full AI-powered analysis with real market data, ensure your Anthropic API key is configured and has available credits.*
"""
