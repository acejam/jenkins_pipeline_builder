class ParametersHelper < ExtensionHelper
  def param_type(param)
    case param[:type]
    when 'string'
      'hudson.model.StringParameterDefinition'
    when 'bool'
      'hudson.model.BooleanParameterDefinition'
    when 'text'
      'hudson.model.TextParameterDefinition'
    when 'password'
      'hudson.model.PasswordParameterDefinition'
    when 'choice'
      'hudson.model.ChoiceParameterDefinition'
    else
      'hudson.model.StringParameterDefinition'
    end
  end
end