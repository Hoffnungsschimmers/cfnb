"""测试带宽测速模块"""

import pytest
from unittest.mock import AsyncMock, patch
from cfnb.config import Config
from cfnb.speed import (
    SpeedResult,
    run_multi_pass_speed_test_async,
    run_speed_test_with_retry,
)


@pytest.mark.anyio
async def test_run_multi_pass_speed_test_async():
    """测试多轮自适应测速流程"""
    candidates = ["1.1.1.1:443#US", "2.2.2.2:443#HK", "3.3.3.3:443#JP"]
    
    config = type(
        "Config",
        (),
        {
            "BANDWIDTH_WORKERS": 2,
            "BANDWIDTH_TIMEOUT": 5,
            "BANDWIDTH_CONNECT_TIMEOUT": 2,
            "BANDWIDTH_SIZE_MB": 0.5,
            "BANDWIDTH_URL_TEMPLATE": "https://speed.cloudflare.com/__down?bytes={bytes}",
            "GLOBAL_TOP_N": 2,
            "BANDWIDTH_RETRY_MAX": 1,
            "BANDWIDTH_RETRY_DELAY": 1,
        },
    )()

    # Mock measure_bandwidth_async to return simulated results
    # Pass 1 (probe 256KB): HK and JP are fast, US is slow
    # Pass 2 (refine 1MB): HK is faster than JP
    mock_results = {
        # Probe (256KB)
        "https://speed.cloudflare.com/__down?bytes=262144": {
            "1.1.1.1:443#US": SpeedResult("1.1.1.1:443#US", 5.0),
            "2.2.2.2:443#HK": SpeedResult("2.2.2.2:443#HK", 15.0),
            "3.3.3.3:443#JP": SpeedResult("3.3.3.3:443#JP", 12.0),
        },
        # Refine (1MB = 1048576 bytes)
        "https://speed.cloudflare.com/__down?bytes=1048576": {
            "2.2.2.2:443#HK": SpeedResult("2.2.2.2:443#HK", 25.0),
            "3.3.3.3:443#JP": SpeedResult("3.3.3.3:443#JP", 18.0),
            "1.1.1.1:443#US": SpeedResult("1.1.1.1:443#US", 3.0),
        }
    }

    async def mock_measure(node, url, timeout, connect_timeout):
        return mock_results.get(url, {}).get(node, SpeedResult(node, 0.0))

    with patch("cfnb.speed.measure_bandwidth_async", new=AsyncMock(side_effect=mock_measure)):
        results = await run_multi_pass_speed_test_async(candidates, config)
        
        assert len(results) == 3
        # Check sorting order (HK > JP > US)
        assert results[0].node == "2.2.2.2:443#HK"
        assert results[0].speed_mbps == 25.0
        assert results[1].node == "3.3.3.3:443#JP"
        assert results[1].speed_mbps == 18.0
        assert results[2].node == "1.1.1.1:443#US"
        assert results[2].speed_mbps == 3.0  # From refine (refine takes priority over probe)
