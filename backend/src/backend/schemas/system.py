from datetime import datetime, timezone

from pydantic import BaseModel, Field


class CpuMetrics(BaseModel):
    usage_percent: float = 0.0
    per_core_percent: list[float] = Field(default_factory=list)
    logical_cores: int = 0
    physical_cores: int | None = None
    frequency_mhz: float | None = None
    max_frequency_mhz: float | None = None
    load_1m: float = 0.0
    load_5m: float = 0.0
    load_15m: float = 0.0


class MemoryMetrics(BaseModel):
    total_bytes: int = 0
    available_bytes: int = 0
    used_bytes: int = 0
    usage_percent: float = 0.0
    cached_bytes: int = 0
    swap_total_bytes: int = 0
    swap_used_bytes: int = 0
    swap_percent: float = 0.0


class DiskMetrics(BaseModel):
    device: str
    mountpoint: str
    filesystem: str
    total_bytes: int
    used_bytes: int
    free_bytes: int
    usage_percent: float


class DiskIoMetrics(BaseModel):
    read_bytes: int = 0
    write_bytes: int = 0
    read_bytes_per_second: float = 0.0
    write_bytes_per_second: float = 0.0


class NetworkInterfaceMetrics(BaseModel):
    name: str
    addresses: list[str] = Field(default_factory=list)
    is_up: bool = False
    speed_mbps: int = 0
    bytes_sent: int = 0
    bytes_received: int = 0


class NetworkMetrics(BaseModel):
    bytes_sent: int = 0
    bytes_received: int = 0
    sent_bytes_per_second: float = 0.0
    received_bytes_per_second: float = 0.0
    interfaces: list[NetworkInterfaceMetrics] = Field(default_factory=list)


class TemperatureMetric(BaseModel):
    sensor: str
    label: str
    current_celsius: float
    high_celsius: float | None = None
    critical_celsius: float | None = None


class ProcessMetric(BaseModel):
    pid: int
    name: str
    status: str
    cpu_percent: float
    memory_percent: float
    resident_bytes: int


class BackendProcessMetrics(BaseModel):
    pid: int
    cpu_percent: float
    memory_percent: float
    resident_bytes: int
    threads: int
    open_files: int | None = None


class GpuMetrics(BaseModel):
    name: str
    usage_percent: float | None = None
    memory_used_bytes: int | None = None
    memory_total_bytes: int | None = None
    temperature_celsius: float | None = None
    power_watts: float | None = None


class SystemIdentity(BaseModel):
    hostname: str
    operating_system: str
    kernel: str
    architecture: str
    cpu_model: str | None = None
    boot_time: datetime
    uptime_seconds: float


class SystemSnapshot(BaseModel):
    timestamp: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
    )
    identity: SystemIdentity
    cpu: CpuMetrics
    memory: MemoryMetrics
    disks: list[DiskMetrics] = Field(default_factory=list)
    disk_io: DiskIoMetrics = Field(default_factory=DiskIoMetrics)
    network: NetworkMetrics = Field(default_factory=NetworkMetrics)
    temperatures: list[TemperatureMetric] = Field(default_factory=list)
    top_processes: list[ProcessMetric] = Field(default_factory=list)
    backend_process: BackendProcessMetrics
    gpus: list[GpuMetrics] = Field(default_factory=list)
