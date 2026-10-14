// Pure configuration and binding rules shared by the controller and tests.
export function valid_name(value) {
    return type(value)=='string' && length(value)<=64 && !!match(value,/^[A-Za-z0-9_]/) && !match(value,/[^A-Za-z0-9_.-]/);
};
export function validate_settings(input, generation) {
    if (type(input)!='object' || input.schema_version!==1 || type(input.enabled)!='bool' || type(input.mappings)!='array' || length(input.mappings)>32) die('invalid_mapping_config');
    let fields=keys(input);
    for (let i=0;i<length(fields);i++) if (index(['schema_version','generation','enabled','mappings'],fields[i])<0) die('unknown_mapping_setting');
    let sources=[],targets=[],rows=[];
    for (let i=0;i<length(input.mappings);i++) {
        let row=input.mappings[i];
        if (type(row)!='object' || !valid_name(row.source_interface) || !valid_name(row.mwan3_interface) || type(row.enabled)!='bool') die('invalid_mapping');
        let names=keys(row);
        for (let j=0;j<length(names);j++) if (index(['source_interface','mwan3_interface','enabled'],names[j])<0) die('unknown_mapping_field');
        if (index(sources,row.source_interface)>=0) die('duplicate_source_interface');
        if (index(targets,row.mwan3_interface)>=0) die('duplicate_mwan3_interface');
        push(sources,row.source_interface);push(targets,row.mwan3_interface);
        push(rows,{source_interface:row.source_interface,mwan3_interface:row.mwan3_interface,enabled:row.enabled});
    }
    return {schema_version:1,generation,enabled:input.enabled,mappings:rows};
};
export function interface_catalog(values) {
    if (type(values)!='object') return [];
    let names=keys(values || {}),result=[];
    for (let i=0;i<length(names);i++) {
        let name=names[i],section=values[name];
        if (type(section)!='object' || section['.type']!='interface' || !valid_name(name)) continue;
        let members=[];
        for (let j=0;j<length(names);j++) {
            let member=values[names[j]];
            if (type(member)=='object' && member['.type']=='member' && member.interface==name) push(members,names[j]);
        }
        push(result,{name,enabled:section.enabled=='1',family:section.family || 'ipv4',members,
            prepared:!length(section.track_ip || []) && section.track_gateway!='1' && section.initial_state=='offline'});
    }
    return result;
};
export function validate_selection(config, sources, interfaces) {
    if (!config.enabled) return;
    for (let i=0;i<length(config.mappings);i++) {
        let row=config.mappings[i];if (!row.enabled) continue;
        if (index(sources,row.source_interface)<0) die('source_interface_missing:'+row.source_interface);
        let target=null;
        for (let j=0;j<length(interfaces);j++) if (interfaces[j].name==row.mwan3_interface) target=interfaces[j];
        if (!target) die('mwan3_interface_missing:'+row.mwan3_interface);
        if (!target.enabled) die('mwan3_interface_disabled:'+target.name);
        if (target.family!='ipv4') die('ipv6_unsupported:'+target.name);
        if (!target.prepared || target.tracker_running) die('tracking_conflict:'+target.name);
    }
};
export function binding_allowed(mapping, network, source, target, previous) {
    if (mapping.source_interface==network) return true;
    if (source?.up && target?.up) return !!source.device && !!source.ip && source.device==target.device && source.ip==target.ip;
    return !source?.up && target?.up && previous?.mapped_source==mapping.source_interface &&
        previous?.target_network==network && previous?.verified_binding==target.device+'/'+target.ip;
};
