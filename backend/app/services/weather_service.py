from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime
from time import monotonic
from typing import Any

import httpx

from app.schemas.outfit import OutfitLocation, OutfitWeatherContext


class WeatherUnavailable(Exception):
    """The forecast provider could not provide a usable outfit-weather context."""


@dataclass(slots=True)
class _CacheEntry:
    value: Any
    expires_at: float


_WEATHER_CODES = {
    0: "clear sky", 1: "mostly clear", 2: "partly cloudy", 3: "overcast",
    45: "foggy", 48: "rime fog", 51: "light drizzle", 53: "drizzle",
    55: "heavy drizzle", 56: "freezing drizzle", 57: "heavy freezing drizzle",
    61: "light rain", 63: "rain", 65: "heavy rain", 66: "freezing rain",
    67: "heavy freezing rain", 71: "light snow", 73: "snow", 75: "heavy snow",
    77: "snow grains", 80: "rain showers", 81: "rain showers",
    82: "heavy rain showers", 85: "snow showers", 86: "heavy snow showers",
    95: "thunderstorm", 96: "thunderstorm with hail", 99: "severe thunderstorm with hail",
}


class WeatherService:
    """Process-local Open-Meteo cache with safe coordinate granularity."""

    _forecast_url = "https://api.open-meteo.com/v1/forecast"
    _geocoding_url = "https://geocoding-api.open-meteo.com/v1/search"

    def __init__(self) -> None:
        self._cache: dict[str, _CacheEntry] = {}
        self._inflight: dict[str, asyncio.Task[Any]] = {}
        self._lock = asyncio.Lock()

    async def search_locations(self, query: str) -> list[OutfitLocation]:
        key = f"geocode:{query.strip().casefold()}"

        async def fetch() -> list[OutfitLocation]:
            payload = await self._request_json(
                self._geocoding_url,
                {"name": query, "count": 8, "language": "en", "format": "json"},
            )
            results = payload.get("results", [])
            if not isinstance(results, list):
                return []
            locations = []
            for result in results:
                if not isinstance(result, dict):
                    continue
                name, latitude, longitude = result.get("name"), result.get("latitude"), result.get("longitude")
                if not isinstance(name, str) or not isinstance(latitude, (int, float)) or not isinstance(longitude, (int, float)):
                    continue
                labels = [name, result.get("admin1"), result.get("country")]
                locations.append(OutfitLocation(
                    name=", ".join(part for part in labels if isinstance(part, str) and part),
                    latitude=latitude,
                    longitude=longitude,
                ))
            return locations

        return await self._get_or_fetch(key, ttl_seconds=24 * 60 * 60, fetcher=fetch)

    async def get_context(self, *, location: OutfitLocation, wear_at: datetime) -> OutfitWeatherContext:
        target_hour = wear_at.replace(minute=0, second=0, microsecond=0)
        # 0.02 degrees avoids retaining a street-level coordinate in the cache.
        latitude, longitude = round(location.latitude, 2), round(location.longitude, 2)
        key = f"weather:{latitude:.2f}:{longitude:.2f}:{target_hour.isoformat()}"
        ttl_seconds = 10 * 60 if (wear_at - datetime.now()).total_seconds() <= 24 * 60 * 60 else 60 * 60

        async def fetch() -> OutfitWeatherContext:
            payload = await self._request_json(
                self._forecast_url,
                {
                    "latitude": latitude, "longitude": longitude, "timezone": "auto", "forecast_days": 16,
                    "hourly": "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_gusts_10m",
                },
            )
            return self._context_from_payload(payload, location.name, target_hour)

        return await self._get_or_fetch(key, ttl_seconds=ttl_seconds, fetcher=fetch)

    async def _get_or_fetch(self, key: str, *, ttl_seconds: int, fetcher: Any) -> Any:
        async with self._lock:
            cached = self._cache.get(key)
            if cached is not None and cached.expires_at > monotonic():
                return cached.value
            task = self._inflight.get(key)
            if task is None:
                task = asyncio.create_task(self._fetch_and_cache(key, ttl_seconds, fetcher))
                self._inflight[key] = task
        return await task

    async def _fetch_and_cache(self, key: str, ttl_seconds: int, fetcher: Any) -> Any:
        try:
            value = await fetcher()
            async with self._lock:
                self._cache[key] = _CacheEntry(value=value, expires_at=monotonic() + ttl_seconds)
                if len(self._cache) > 200:
                    now = monotonic()
                    self._cache = {cache_key: entry for cache_key, entry in self._cache.items() if entry.expires_at > now}
            return value
        finally:
            async with self._lock:
                self._inflight.pop(key, None)

    async def _request_json(self, url: str, params: dict[str, Any]) -> dict[str, Any]:
        # Two attempts stay inside the five-second weather budget.
        timeout = httpx.Timeout(2.3, connect=0.8)
        last_error: Exception | None = None
        for attempt in range(2):
            try:
                async with httpx.AsyncClient(timeout=timeout) as client:
                    response = await client.get(url, params=params)
                    response.raise_for_status()
                    payload = response.json()
                    if not isinstance(payload, dict):
                        raise ValueError("Weather provider returned an invalid response")
                    return payload
            except (httpx.HTTPError, ValueError) as error:
                last_error = error
                if attempt == 0:
                    await asyncio.sleep(0.2)
        raise WeatherUnavailable("Weather provider is unavailable") from last_error

    @staticmethod
    def _context_from_payload(payload: dict[str, Any], location_name: str, target_hour: datetime) -> OutfitWeatherContext:
        hourly = payload.get("hourly")
        if not isinstance(hourly, dict) or not isinstance(hourly.get("time"), list):
            raise WeatherUnavailable("Weather provider did not return hourly forecast data")
        target_key = target_hour.strftime("%Y-%m-%dT%H:00")
        try:
            index = hourly["time"].index(target_key)
        except ValueError as error:
            raise WeatherUnavailable("The selected time is outside the available forecast") from error

        def number(name: str) -> float | None:
            values = hourly.get(name)
            value = values[index] if isinstance(values, list) and index < len(values) else None
            return float(value) if isinstance(value, (int, float)) else None

        weather_code, temperature, apparent_temperature = number("weather_code"), number("temperature_2m"), number("apparent_temperature")
        if weather_code is None or temperature is None or apparent_temperature is None:
            raise WeatherUnavailable("Weather provider returned incomplete forecast data")
        condition = _WEATHER_CODES.get(int(weather_code), "variable conditions")
        precipitation_probability, precipitation = number("precipitation_probability"), number("precipitation")
        humidity, wind_speed, wind_gusts = number("relative_humidity_2m"), number("wind_speed_10m"), number("wind_gusts_10m")
        return OutfitWeatherContext(
            location_name=location_name, local_time=target_hour,
            time_of_day=WeatherService._time_of_day(target_hour.hour), condition=condition,
            temperature_c=round(temperature, 1), apparent_temperature_c=round(apparent_temperature, 1),
            precipitation_probability=round(precipitation_probability) if precipitation_probability is not None else None,
            precipitation_mm=round(precipitation, 1) if precipitation is not None else None,
            humidity_percent=round(humidity) if humidity is not None else None,
            wind_speed_kmh=round(wind_speed, 1) if wind_speed is not None else None,
            wind_gusts_kmh=round(wind_gusts, 1) if wind_gusts is not None else None,
            considerations=WeatherService._considerations(
                temperature, apparent_temperature, condition, precipitation_probability, wind_speed, humidity,
            ),
        )

    @staticmethod
    def _time_of_day(hour: int) -> str:
        if 5 <= hour < 12:
            return "morning"
        if 12 <= hour < 17:
            return "afternoon"
        if 17 <= hour < 21:
            return "evening"
        return "night"

    @staticmethod
    def _considerations(temperature: float, apparent_temperature: float, condition: str, precipitation_probability: float | None, wind_speed: float | None, humidity: float | None) -> list[str]:
        considerations: list[str] = []
        if apparent_temperature >= 30:
            considerations.append("hot; favour breathable, lightweight layers")
        elif apparent_temperature <= 15:
            considerations.append("cool; consider a warm layer")
        elif temperature >= 26:
            considerations.append("warm; favour breathable fabrics")
        if precipitation_probability is not None and precipitation_probability >= 50:
            considerations.append("rain is likely; favour rain-friendly footwear and an easy outer layer")
        if "thunderstorm" in condition or "heavy rain" in condition:
            considerations.append("wet-weather protection is important")
        if wind_speed is not None and wind_speed >= 25:
            considerations.append("windy; avoid impractical loose layers")
        if humidity is not None and humidity >= 75:
            considerations.append("humid; favour comfortable, breathable fabrics")
        return considerations or ["conditions are comfortable for a normal outfit"]


weather_service = WeatherService()
