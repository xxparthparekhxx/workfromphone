import asyncio
from datetime import datetime, timezone
import os
import platform
import socket
import subprocess
import threading
import time

import psutil
from fastapi import WebSocket, WebSocketDisconnect

from backend.schemas.system import (
    BackendProcessMetrics,
    CpuMetrics,
    DiskIoMetrics,
    DiskMetrics,
    GpuMetrics,
    MemoryMetrics,
    NetworkInterfaceMetrics,
    NetworkMetrics,
    ProcessMetric,
    SystemIdentity,
    SystemSnapshot,
    TemperatureMetric,
)


_IGNORED_FILESYSTEMS = {
    "autofs",
    "binfmt_misc",
    "cgroup",
    "cgroup2",
    "configfs",
    "debugfs",
    "devpts",
    "devtmpfs",
    "fusectl",
    "hugetlbfs",
    "mqueue",
    "overlay",
    "proc",
    "pstore",
    "securityfs",
    "sysfs",
    "tmpfs",
    "tracefs",
}


class SystemService:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._last_sample_time: float | None = None
        self._last_disk_read = 0
        self._last_disk_write = 0
        self._last_net_sent = 0
        self._last_net_received = 0
        self._gpu_cache: tuple[float, list[GpuMetrics]] = (0.0, [])

    @staticmethod
    def _cpu_model() -> str | None:
        try:
            with open("/proc/cpuinfo", encoding="utf-8") as cpuinfo:
                for line in cpuinfo:
                    if line.lower().startswith(("model name", "hardware")):
                        return line.split(":", 1)[1].strip() or None
        except OSError:
            return None
        return None

    @staticmethod
    def _operating_system() -> str:
        try:
            release = platform.freedesktop_os_release()
            return release.get("PRETTY_NAME") or release.get("NAME") or platform.system()
        except OSError:
            return platform.platform()

    @staticmethod
    def _disks() -> list[DiskMetrics]:
        disks: list[DiskMetrics] = []
        seen_mountpoints: set[str] = set()
        for partition in psutil.disk_partitions(all=False):
            if (
                partition.mountpoint in seen_mountpoints
                or partition.fstype.lower() in _IGNORED_FILESYSTEMS
            ):
                continue
            try:
                usage = psutil.disk_usage(partition.mountpoint)
            except (OSError, PermissionError):
                continue
            seen_mountpoints.add(partition.mountpoint)
            disks.append(
                DiskMetrics(
                    device=partition.device,
                    mountpoint=partition.mountpoint,
                    filesystem=partition.fstype,
                    total_bytes=usage.total,
                    used_bytes=usage.used,
                    free_bytes=usage.free,
                    usage_percent=usage.percent,
                ),
            )
        return sorted(disks, key=lambda disk: disk.mountpoint)

    @staticmethod
    def _network_interfaces() -> list[NetworkInterfaceMetrics]:
        addresses = psutil.net_if_addrs()
        stats = psutil.net_if_stats()
        counters = psutil.net_io_counters(pernic=True)
        result: list[NetworkInterfaceMetrics] = []
        for name in sorted(set(addresses) | set(stats)):
            interface_addresses = [
                address.address
                for address in addresses.get(name, [])
                if address.family in {socket.AF_INET, socket.AF_INET6}
            ]
            stat = stats.get(name)
            counter = counters.get(name)
            result.append(
                NetworkInterfaceMetrics(
                    name=name,
                    addresses=interface_addresses,
                    is_up=stat.isup if stat else False,
                    speed_mbps=max(0, stat.speed) if stat else 0,
                    bytes_sent=counter.bytes_sent if counter else 0,
                    bytes_received=counter.bytes_recv if counter else 0,
                ),
            )
        return result

    @staticmethod
    def _temperatures() -> list[TemperatureMetric]:
        try:
            sensors = psutil.sensors_temperatures(fahrenheit=False)
        except (AttributeError, OSError):
            return []

        temperatures: list[TemperatureMetric] = []
        for sensor, entries in sensors.items():
            for index, entry in enumerate(entries):
                temperatures.append(
                    TemperatureMetric(
                        sensor=sensor,
                        label=entry.label or f"Sensor {index + 1}",
                        current_celsius=entry.current,
                        high_celsius=entry.high,
                        critical_celsius=entry.critical,
                    ),
                )
        return temperatures

    @staticmethod
    def _top_processes(limit: int = 8) -> list[ProcessMetric]:
        processes: list[ProcessMetric] = []
        attributes = ["pid", "name", "status", "cpu_percent", "memory_percent", "memory_info"]
        for process in psutil.process_iter(attributes):
            try:
                info = process.info
                processes.append(
                    ProcessMetric(
                        pid=info["pid"],
                        name=info["name"] or "unknown",
                        status=info["status"] or "unknown",
                        cpu_percent=float(info["cpu_percent"] or 0.0),
                        memory_percent=float(info["memory_percent"] or 0.0),
                        resident_bytes=int(info["memory_info"].rss),
                    ),
                )
            except (psutil.AccessDenied, psutil.NoSuchProcess, KeyError, AttributeError):
                continue
        processes.sort(
            key=lambda process: (process.cpu_percent, process.memory_percent),
            reverse=True,
        )
        return processes[:limit]

    def _gpus(self, now: float) -> list[GpuMetrics]:
        cached_at, cached_gpus = self._gpu_cache
        if now - cached_at < 10:
            return cached_gpus
        try:
            command = [
                "nvidia-smi",
                "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
                "--format=csv,noheader,nounits",
            ]
            result = subprocess.run(
                command,
                capture_output=True,
                check=True,
                text=True,
                timeout=2,
            )
            gpus = []
            for line in result.stdout.splitlines():
                values = [value.strip() for value in line.split(",")]
                if len(values) != 6:
                    continue
                gpus.append(
                    GpuMetrics(
                        name=values[0],
                        usage_percent=float(values[1]),
                        memory_used_bytes=int(float(values[2]) * 1024 * 1024),
                        memory_total_bytes=int(float(values[3]) * 1024 * 1024),
                        temperature_celsius=float(values[4]),
                        power_watts=float(values[5]),
                    ),
                )
        except (FileNotFoundError, subprocess.SubprocessError, ValueError):
            gpus = []
        self._gpu_cache = (now, gpus)
        return gpus

    def _snapshot(self) -> SystemSnapshot:
        with self._lock:
            now_monotonic = time.monotonic()
            now = datetime.now(timezone.utc)
            elapsed = (
                max(now_monotonic - self._last_sample_time, 0.001)
                if self._last_sample_time is not None
                else None
            )

            disk_io = psutil.disk_io_counters()
            net_io = psutil.net_io_counters()
            disk_read = disk_io.read_bytes if disk_io else 0
            disk_write = disk_io.write_bytes if disk_io else 0
            net_sent = net_io.bytes_sent if net_io else 0
            net_received = net_io.bytes_recv if net_io else 0

            disk_read_rate = (
                max(0, disk_read - self._last_disk_read) / elapsed if elapsed else 0.0
            )
            disk_write_rate = (
                max(0, disk_write - self._last_disk_write) / elapsed if elapsed else 0.0
            )
            net_sent_rate = (
                max(0, net_sent - self._last_net_sent) / elapsed if elapsed else 0.0
            )
            net_received_rate = (
                max(0, net_received - self._last_net_received) / elapsed
                if elapsed
                else 0.0
            )

            self._last_sample_time = now_monotonic
            self._last_disk_read = disk_read
            self._last_disk_write = disk_write
            self._last_net_sent = net_sent
            self._last_net_received = net_received

            virtual_memory = psutil.virtual_memory()
            swap = psutil.swap_memory()
            frequency = psutil.cpu_freq()
            load_1m, load_5m, load_15m = os.getloadavg()
            boot_time = datetime.fromtimestamp(psutil.boot_time(), timezone.utc)
            backend = psutil.Process()
            try:
                open_files = len(backend.open_files())
            except (psutil.AccessDenied, NotImplementedError):
                open_files = None

            return SystemSnapshot(
                timestamp=now,
                identity=SystemIdentity(
                    hostname=platform.node(),
                    operating_system=self._operating_system(),
                    kernel=platform.release(),
                    architecture=platform.machine(),
                    cpu_model=self._cpu_model(),
                    boot_time=boot_time,
                    uptime_seconds=max(0.0, now.timestamp() - boot_time.timestamp()),
                ),
                cpu=CpuMetrics(
                    usage_percent=psutil.cpu_percent(interval=None),
                    per_core_percent=psutil.cpu_percent(interval=None, percpu=True),
                    logical_cores=psutil.cpu_count(logical=True) or 0,
                    physical_cores=psutil.cpu_count(logical=False),
                    frequency_mhz=frequency.current if frequency else None,
                    max_frequency_mhz=frequency.max if frequency else None,
                    load_1m=load_1m,
                    load_5m=load_5m,
                    load_15m=load_15m,
                ),
                memory=MemoryMetrics(
                    total_bytes=virtual_memory.total,
                    available_bytes=virtual_memory.available,
                    used_bytes=virtual_memory.used,
                    usage_percent=virtual_memory.percent,
                    cached_bytes=getattr(virtual_memory, "cached", 0),
                    swap_total_bytes=swap.total,
                    swap_used_bytes=swap.used,
                    swap_percent=swap.percent,
                ),
                disks=self._disks(),
                disk_io=DiskIoMetrics(
                    read_bytes=disk_read,
                    write_bytes=disk_write,
                    read_bytes_per_second=disk_read_rate,
                    write_bytes_per_second=disk_write_rate,
                ),
                network=NetworkMetrics(
                    bytes_sent=net_sent,
                    bytes_received=net_received,
                    sent_bytes_per_second=net_sent_rate,
                    received_bytes_per_second=net_received_rate,
                    interfaces=self._network_interfaces(),
                ),
                temperatures=self._temperatures(),
                top_processes=self._top_processes(),
                backend_process=BackendProcessMetrics(
                    pid=backend.pid,
                    cpu_percent=backend.cpu_percent(interval=None),
                    memory_percent=backend.memory_percent(),
                    resident_bytes=backend.memory_info().rss,
                    threads=backend.num_threads(),
                    open_files=open_files,
                ),
                gpus=self._gpus(now_monotonic),
            )

    async def snapshot(self) -> SystemSnapshot:
        return await asyncio.to_thread(self._snapshot)

    async def handle_websocket(self, websocket: WebSocket, interval: float) -> None:
        await websocket.accept()
        try:
            while True:
                snapshot = await self.snapshot()
                await websocket.send_json(snapshot.model_dump(mode="json"))
                await asyncio.sleep(interval)
        except (WebSocketDisconnect, RuntimeError):
            return


system_service = SystemService()
