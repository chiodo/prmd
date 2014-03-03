def extract_attributes(schema, properties)
  attributes = []
  properties.each do |key, value|
    # found a reference to another element:
    if value.has_key?('anyOf')
      descriptions = []
      examples = []

      # sort anyOf! always show unique identifier first
      anyof = value['anyOf'].sort_by do |property|
        property['$ref'].split('/').last.gsub('id', 'a')
      end

      anyof.each do |ref|
        nested_field = schema.dereference(ref)
        descriptions << nested_field['description']
        examples << nested_field['example']
      end

      # avoid repetition :}
      if descriptions.size > 1
        descriptions.first.gsub!(/ of (this )?.*/, "")
        descriptions[1..-1].map { |d| d.gsub!(/unique /, "") }
      end
      description = descriptions.join(" or ")
      example = doc_example(*examples)
      attributes << [key, "string", description, example]

    # found a nested object
    elsif value['type'] == ['object'] && value['properties']
      properties = value['properties'].sort_by { |k, v| k }

      properties.each do |prop_name, prop_value|
        prop_value = schema.dereference(prop_value)
        new_key = "#{key}:#{prop_name}"
        attributes << [new_key, doc_type(prop_value),
          prop_value['description'], doc_example(prop_value['example'])]
      end

    # just a regular attribute
    else
      value = schema.dereference(value)
      description = value['description']
      if value['enum']
        description += '<br/><b>one of:</b>' + doc_example(*value['enum'])
      end
      example = doc_example(value['example'])
      attributes << [key, doc_type(value),
        description, example]
    end
  end
  return attributes
end

def doc_type(property)
  schema_type = property["type"].dup
  type = "nullable " if schema_type.delete("null")
  type.to_s + (property["format"] || schema_type.first)
end

def doc_example(*examples)
  examples.map { |e| "<code>#{e.to_json}</code>" }.join(" or ")
end

module Prmd
  def self.doc(path)
    if File.directory?(path)
      devcenter_header_path = File.join(path, 'devcenter_header.md')
      if File.exists?(devcenter_header_path)
        puts File.read(File.join(path, 'devcenter_header.md'))
      end
      overview_path = File.join(path, 'overview.md')
      if File.exists?(overview_path)
        puts File.read(File.join(path, 'overview.md'))
      end
    end
    schema = Prmd::Schema.load(path)

    schema.data['definitions'].each do |_, definition|
      next if (definition['links'] || []).empty?
      resource = definition['id'].split('/').last
      serialization = {}
      if definition['definitions'].has_key?('identity')
        identifiers = if definition['definitions']['identity'].has_key?('anyOf')
          definition['definitions']['identity']['anyOf']
        else
          [definitions['definitions']['identity']]
        end

        identifiers = identifiers.map {|ref| ref['$ref'].split('/').last }
      end
      if definition['properties']
        definition['properties'].each do |key, value|
          unless value.has_key?('properties')
            serialization[key] = schema.dereference(value)['example']
          else
            serialization[key] = {}
            value['properties'].each do |k,v|
              serialization[key][k] = schema.dereference(v)['example']
            end
          end
        end
      else
        serialization.merge!(definition['example'])
      end

      title = definition['title'].split(' - ', 2).last

      puts Erubis::Eruby.new(File.read(File.dirname(__FILE__) + "/../views/endpoint.erb")).result({
        definition:      definition,
        identifiers:     identifiers,
        resource:        resource,
        schema:          schema,
        serialization:   serialization,
        title:           title,
        params_template: File.read(File.dirname(__FILE__) + "/../views/parameters.erb"),
      })
    end
  end
end
