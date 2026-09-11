// Generated from FLECS_API extern declarations in flecs.h.
// Run scripts/generate_globals.ps1 after upgrading the vendored Flecs version.
package oflecs

// The system libraries are repeated from oflecs.odin so that a compilation
// unit referencing only exported globals still links them: Odin's dead code
// elimination drops a foreign import block, including its system libraries,
// when nothing in it is referenced.
when ODIN_OS == .Windows {
	foreign import globals_lib {
		"windows/oflecs.lib",
		"system:Ws2_32.lib",
		"system:Dbghelp.lib",
	}
} else when ODIN_OS == .Linux {
	when ODIN_ARCH == .arm64 {
		foreign import globals_lib {
			"linux-arm64/liboflecs.a",
			"system:pthread",
			"system:dl",
			"system:m",
		}
	} else {
		foreign import globals_lib {
			"linux/liboflecs.a",
			"system:pthread",
			"system:dl",
			"system:m",
		}
	}
} else when ODIN_OS == .Darwin {
	when ODIN_ARCH == .arm64 {
		foreign import globals_lib "macos-arm64/liboflecs.a"
	} else {
		foreign import globals_lib "macos/liboflecs.a"
	}
} else {
	foreign import globals_lib "system:oflecs"
}

foreign globals_lib {
	ecs_os_api_malloc_count: i64
	ecs_os_api_realloc_count: i64
	ecs_os_api_calloc_count: i64
	ecs_os_api_free_count: i64
	ecs_os_api: ecs_os_api_t
	@(link_name="FLECS_IDEcsComponentID_")
	EcsComponent_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsIdentifierID_")
	EcsIdentifier_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsPolyID_")
	EcsPoly_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsParentID_")
	EcsParent_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsTreeSpawnerID_")
	EcsTreeSpawner_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsDefaultChildComponentID_")
	EcsDefaultChildComponent_ID: ecs_entity_t
	EcsParentDepth: ecs_entity_t
	EcsQuery: ecs_entity_t
	EcsObserver: ecs_entity_t
	EcsSystem: ecs_entity_t
	@(link_name="FLECS_IDEcsTickSourceID_")
	EcsTickSource_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsTimerID_")
	EcsTimer_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsRateFilterID_")
	EcsRateFilter_ID: ecs_entity_t
	EcsFlecs: ecs_entity_t
	EcsFlecsCore: ecs_entity_t
	EcsWorld: ecs_entity_t
	EcsWildcard: ecs_entity_t
	EcsAny: ecs_entity_t
	EcsThis: ecs_entity_t
	EcsVariable: ecs_entity_t
	EcsTransitive: ecs_entity_t
	EcsReflexive: ecs_entity_t
	EcsFinal: ecs_entity_t
	EcsInheritable: ecs_entity_t
	EcsOnInstantiate: ecs_entity_t
	EcsOverride: ecs_entity_t
	EcsInherit: ecs_entity_t
	EcsDontInherit: ecs_entity_t
	EcsSymmetric: ecs_entity_t
	EcsExclusive: ecs_entity_t
	EcsAcyclic: ecs_entity_t
	EcsTraversable: ecs_entity_t
	EcsWith: ecs_entity_t
	EcsOneOf: ecs_entity_t
	EcsCanToggle: ecs_entity_t
	EcsTrait: ecs_entity_t
	EcsRelationship: ecs_entity_t
	EcsTarget: ecs_entity_t
	EcsPairIsTag: ecs_entity_t
	EcsName: ecs_entity_t
	EcsSymbol: ecs_entity_t
	EcsAlias: ecs_entity_t
	EcsChildOf: ecs_entity_t
	EcsIsA: ecs_entity_t
	EcsDependsOn: ecs_entity_t
	EcsSlotOf: ecs_entity_t
	EcsOrderedChildren: ecs_entity_t
	EcsModule: ecs_entity_t
	EcsPrefab: ecs_entity_t
	EcsDisabled: ecs_entity_t
	EcsNotQueryable: ecs_entity_t
	EcsOnAdd: ecs_entity_t
	EcsOnRemove: ecs_entity_t
	EcsOnSet: ecs_entity_t
	EcsMonitor: ecs_entity_t
	EcsOnTableCreate: ecs_entity_t
	EcsOnTableDelete: ecs_entity_t
	EcsOnDelete: ecs_entity_t
	EcsOnDeleteTarget: ecs_entity_t
	EcsRemove: ecs_entity_t
	EcsDelete: ecs_entity_t
	EcsPanic: ecs_entity_t
	EcsSingleton: ecs_entity_t
	EcsSparse: ecs_entity_t
	EcsDontFragment: ecs_entity_t
	EcsPredEq: ecs_entity_t
	EcsPredMatch: ecs_entity_t
	EcsPredLookup: ecs_entity_t
	EcsScopeOpen: ecs_entity_t
	EcsScopeClose: ecs_entity_t
	EcsEmpty: ecs_entity_t
	@(link_name="FLECS_IDEcsPipelineID_")
	EcsPipeline_ID: ecs_entity_t
	EcsOnStart: ecs_entity_t
	EcsPreFrame: ecs_entity_t
	EcsOnLoad: ecs_entity_t
	EcsPostLoad: ecs_entity_t
	EcsPreUpdate: ecs_entity_t
	EcsOnUpdate: ecs_entity_t
	EcsOnValidate: ecs_entity_t
	EcsPostUpdate: ecs_entity_t
	EcsPreStore: ecs_entity_t
	EcsOnStore: ecs_entity_t
	EcsPostFrame: ecs_entity_t
	EcsPhase: ecs_entity_t
	EcsConstant: ecs_entity_t
	@(link_name="FLECS_IDEcsRestID_")
	EcsRest_ID: ecs_entity_t
	@(link_name="FLECS_IDFlecsStatsID_")
	FlecsStats_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsWorldStatsID_")
	EcsWorldStats_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsWorldSummaryID_")
	EcsWorldSummary_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsSystemStatsID_")
	EcsSystemStats_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsPipelineStatsID_")
	EcsPipelineStats_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_entities_memory_tID_")
	ecs_entities_memory_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_component_index_memory_tID_")
	ecs_component_index_memory_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_query_memory_tID_")
	ecs_query_memory_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_component_memory_tID_")
	ecs_component_memory_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_table_memory_tID_")
	ecs_table_memory_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_misc_memory_tID_")
	ecs_misc_memory_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_table_histogram_tID_")
	ecs_table_histogram_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_allocator_memory_tID_")
	ecs_allocator_memory_t_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsWorldMemoryID_")
	EcsWorldMemory_ID: ecs_entity_t
	EcsPeriod1s: ecs_entity_t
	EcsPeriod1m: ecs_entity_t
	EcsPeriod1h: ecs_entity_t
	EcsPeriod1d: ecs_entity_t
	EcsPeriod1w: ecs_entity_t
	@(link_name="FLECS_IDFlecsMetricsID_")
	FlecsMetrics_ID: ecs_entity_t
	EcsMetric: ecs_entity_t
	@(link_name="FLECS_IDEcsMetricID_")
	EcsMetric_ID: ecs_entity_t
	EcsCounter: ecs_entity_t
	@(link_name="FLECS_IDEcsCounterID_")
	EcsCounter_ID: ecs_entity_t
	EcsCounterIncrement: ecs_entity_t
	@(link_name="FLECS_IDEcsCounterIncrementID_")
	EcsCounterIncrement_ID: ecs_entity_t
	EcsCounterId: ecs_entity_t
	@(link_name="FLECS_IDEcsCounterIdID_")
	EcsCounterId_ID: ecs_entity_t
	EcsGauge: ecs_entity_t
	@(link_name="FLECS_IDEcsGaugeID_")
	EcsGauge_ID: ecs_entity_t
	EcsMetricInstance: ecs_entity_t
	@(link_name="FLECS_IDEcsMetricInstanceID_")
	EcsMetricInstance_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsMetricValueID_")
	EcsMetricValue_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsMetricSourceID_")
	EcsMetricSource_ID: ecs_entity_t
	@(link_name="FLECS_IDFlecsAlertsID_")
	FlecsAlerts_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsAlertID_")
	EcsAlert_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsAlertInstanceID_")
	EcsAlertInstance_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsAlertsActiveID_")
	EcsAlertsActive_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsAlertTimeoutID_")
	EcsAlertTimeout_ID: ecs_entity_t
	EcsAlertInfo: ecs_entity_t
	@(link_name="FLECS_IDEcsAlertInfoID_")
	EcsAlertInfo_ID: ecs_entity_t
	EcsAlertWarning: ecs_entity_t
	@(link_name="FLECS_IDEcsAlertWarningID_")
	EcsAlertWarning_ID: ecs_entity_t
	EcsAlertError: ecs_entity_t
	@(link_name="FLECS_IDEcsAlertErrorID_")
	EcsAlertError_ID: ecs_entity_t
	EcsAlertCritical: ecs_entity_t
	@(link_name="FLECS_IDEcsAlertCriticalID_")
	EcsAlertCritical_ID: ecs_entity_t
	EcsUnitPrefixes: ecs_entity_t
	EcsYocto: ecs_entity_t
	EcsZepto: ecs_entity_t
	EcsAtto: ecs_entity_t
	EcsFemto: ecs_entity_t
	EcsPico: ecs_entity_t
	EcsNano: ecs_entity_t
	EcsMicro: ecs_entity_t
	EcsMilli: ecs_entity_t
	EcsCenti: ecs_entity_t
	EcsDeci: ecs_entity_t
	EcsDeca: ecs_entity_t
	EcsHecto: ecs_entity_t
	EcsKilo: ecs_entity_t
	EcsMega: ecs_entity_t
	EcsGiga: ecs_entity_t
	EcsTera: ecs_entity_t
	EcsPeta: ecs_entity_t
	EcsExa: ecs_entity_t
	EcsZetta: ecs_entity_t
	EcsYotta: ecs_entity_t
	EcsKibi: ecs_entity_t
	EcsMebi: ecs_entity_t
	EcsGibi: ecs_entity_t
	EcsTebi: ecs_entity_t
	EcsPebi: ecs_entity_t
	EcsExbi: ecs_entity_t
	EcsZebi: ecs_entity_t
	EcsYobi: ecs_entity_t
	EcsDuration: ecs_entity_t
	EcsPicoSeconds: ecs_entity_t
	EcsNanoSeconds: ecs_entity_t
	EcsMicroSeconds: ecs_entity_t
	EcsMilliSeconds: ecs_entity_t
	EcsSeconds: ecs_entity_t
	EcsMinutes: ecs_entity_t
	EcsHours: ecs_entity_t
	EcsDays: ecs_entity_t
	EcsTime: ecs_entity_t
	EcsDate: ecs_entity_t
	EcsMass: ecs_entity_t
	EcsGrams: ecs_entity_t
	EcsKiloGrams: ecs_entity_t
	EcsElectricCurrent: ecs_entity_t
	EcsAmpere: ecs_entity_t
	EcsAmount: ecs_entity_t
	EcsMole: ecs_entity_t
	EcsLuminousIntensity: ecs_entity_t
	EcsCandela: ecs_entity_t
	EcsForce: ecs_entity_t
	EcsNewton: ecs_entity_t
	EcsLength: ecs_entity_t
	EcsMeters: ecs_entity_t
	EcsPicoMeters: ecs_entity_t
	EcsNanoMeters: ecs_entity_t
	EcsMicroMeters: ecs_entity_t
	EcsMilliMeters: ecs_entity_t
	EcsCentiMeters: ecs_entity_t
	EcsKiloMeters: ecs_entity_t
	EcsMiles: ecs_entity_t
	EcsPixels: ecs_entity_t
	EcsPressure: ecs_entity_t
	EcsPascal: ecs_entity_t
	EcsBar: ecs_entity_t
	EcsSpeed: ecs_entity_t
	EcsMetersPerSecond: ecs_entity_t
	EcsKiloMetersPerSecond: ecs_entity_t
	EcsKiloMetersPerHour: ecs_entity_t
	EcsMilesPerHour: ecs_entity_t
	EcsTemperature: ecs_entity_t
	EcsKelvin: ecs_entity_t
	EcsCelsius: ecs_entity_t
	EcsFahrenheit: ecs_entity_t
	EcsData: ecs_entity_t
	EcsBits: ecs_entity_t
	EcsKiloBits: ecs_entity_t
	EcsMegaBits: ecs_entity_t
	EcsGigaBits: ecs_entity_t
	EcsBytes: ecs_entity_t
	EcsKiloBytes: ecs_entity_t
	EcsMegaBytes: ecs_entity_t
	EcsGigaBytes: ecs_entity_t
	EcsKibiBytes: ecs_entity_t
	EcsMebiBytes: ecs_entity_t
	EcsGibiBytes: ecs_entity_t
	EcsDataRate: ecs_entity_t
	EcsBitsPerSecond: ecs_entity_t
	EcsKiloBitsPerSecond: ecs_entity_t
	EcsMegaBitsPerSecond: ecs_entity_t
	EcsGigaBitsPerSecond: ecs_entity_t
	EcsBytesPerSecond: ecs_entity_t
	EcsKiloBytesPerSecond: ecs_entity_t
	EcsMegaBytesPerSecond: ecs_entity_t
	EcsGigaBytesPerSecond: ecs_entity_t
	EcsAngle: ecs_entity_t
	EcsRadians: ecs_entity_t
	EcsDegrees: ecs_entity_t
	EcsFrequency: ecs_entity_t
	EcsHertz: ecs_entity_t
	EcsKiloHertz: ecs_entity_t
	EcsMegaHertz: ecs_entity_t
	EcsGigaHertz: ecs_entity_t
	EcsUri: ecs_entity_t
	EcsUriHyperlink: ecs_entity_t
	EcsUriImage: ecs_entity_t
	EcsUriFile: ecs_entity_t
	EcsColor: ecs_entity_t
	EcsColorRgb: ecs_entity_t
	EcsColorHsl: ecs_entity_t
	EcsColorCss: ecs_entity_t
	EcsAcceleration: ecs_entity_t
	EcsPercentage: ecs_entity_t
	EcsBel: ecs_entity_t
	EcsDeciBel: ecs_entity_t
	@(link_name="FLECS_IDEcsScriptID_")
	EcsScript_ID: ecs_entity_t
	EcsScriptTemplate: ecs_entity_t
	@(link_name="FLECS_IDEcsScriptTemplateID_")
	EcsScriptTemplate_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsScriptConstVarID_")
	EcsScriptConstVar_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsScriptFunctionID_")
	EcsScriptFunction_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsScriptMethodID_")
	EcsScriptMethod_ID: ecs_entity_t
	EcsScriptVectorType: ecs_entity_t
	@(link_name="FLECS_IDEcsScriptVectorTypeID_")
	EcsScriptVectorType_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsDocDescriptionID_")
	EcsDocDescription_ID: ecs_entity_t
	EcsDocUuid: ecs_entity_t
	EcsDocBrief: ecs_entity_t
	EcsDocDetail: ecs_entity_t
	EcsDocLink: ecs_entity_t
	EcsDocColor: ecs_entity_t
	@(link_name="FLECS_IDEcsTypeID_")
	EcsType_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsTypeSerializerID_")
	EcsTypeSerializer_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsPrimitiveID_")
	EcsPrimitive_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsEnumID_")
	EcsEnum_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsBitmaskID_")
	EcsBitmask_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsConstantsID_")
	EcsConstants_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsMemberID_")
	EcsMember_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsMemberRangesID_")
	EcsMemberRanges_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsStructID_")
	EcsStruct_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsArrayID_")
	EcsArray_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsVectorID_")
	EcsVector_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsOpaqueID_")
	EcsOpaque_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsUnitID_")
	EcsUnit_ID: ecs_entity_t
	@(link_name="FLECS_IDEcsUnitPrefixID_")
	EcsUnitPrefix_ID: ecs_entity_t
	EcsQuantity: ecs_entity_t
	@(link_name="FLECS_IDecs_bool_tID_")
	ecs_bool_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_char_tID_")
	ecs_char_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_byte_tID_")
	ecs_byte_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_u8_tID_")
	ecs_u8_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_u16_tID_")
	ecs_u16_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_u32_tID_")
	ecs_u32_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_u64_tID_")
	ecs_u64_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_uptr_tID_")
	ecs_uptr_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_i8_tID_")
	ecs_i8_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_i16_tID_")
	ecs_i16_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_i32_tID_")
	ecs_i32_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_i64_tID_")
	ecs_i64_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_iptr_tID_")
	ecs_iptr_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_f32_tID_")
	ecs_f32_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_f64_tID_")
	ecs_f64_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_string_tID_")
	ecs_string_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_entity_tID_")
	ecs_entity_t_ID: ecs_entity_t
	@(link_name="FLECS_IDecs_id_tID_")
	ecs_id_t_ID: ecs_entity_t
}
