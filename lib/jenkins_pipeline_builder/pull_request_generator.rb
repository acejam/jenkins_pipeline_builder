#
# Copyright (c) 2014 Constant Contact
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
module JenkinsPipelineBuilder
  class PullRequestGenerator
    class NotFound < StandardError; end
    attr_accessor :open_prs, :application_name

    def initialize(defaults = {})
      @application_name = defaults[:application_name] || fail('Please set "application_name" in your project!')
      @open_prs = active_prs defaults[:git_url], defaults[:git_org], defaults[:git_repo]
    end

    def convert!(job_collection, pr)
      if pr.class == Hash
        name = "#{application_name}-PR#{pr[:id]}"
        pr_number = pr[:id]
      else
        name = "#{application_name}-PR#{pr}"
        pr_number = pr
      end
      job_collection.defaults[:value][:application_name] = name
      job_collection.defaults[:value][:pull_request_number] = pr_number.to_s
      job_collection.jobs.each { |j| override j[:value], pr }
    end

    def delete_closed_prs
      return if JenkinsPipelineBuilder.debug
      jobs_to_delete = JenkinsPipelineBuilder.client.job.list "^#{application_name}-PR(\\d+)-(.*)$"
      open_prs.each do |n|
        if n.class == Hash
          name = "#{application_name}-PR#{n[:id]}"
        else
          name = "#{application_name}-PR#{n}"
        end
        jobs_to_delete.reject! { |j| j.start_with? name }
      end
      jobs_to_delete.each { |j| JenkinsPipelineBuilder.client.job.delete j }
    end

    private

    def override(job, pr)
      git_version = JenkinsPipelineBuilder.registry.registry[:job][:scm_params].installed_version
      if pr.class == Hash
        scm_branch = pr[:branch]
        refspec = ''
        branch = pr[:branch]
      else
        scm_branch = "origin/pr/#{pr}/head"
        refspec = "refs/pull/#{pr}/head:refs/remotes/origin/pr/#{pr}/head"
        branch = "pr/#{pr}/head"
      end
      job[:scm_branch] = scm_branch
      job[:scm_params] ||= {}
      job[:scm_params][:refspec] = refspec
      job[:scm_params][:changelog_to_branch] ||= {}
      job[:scm_params][:changelog_to_branch]
        .merge!(remote: 'origin', branch: branch) if Gem::Version.new(2.0) < git_version
    end

    def active_prs(git_url, git_org, git_repo)
      (git_url && git_org && git_repo) || fail('Please set git_url, git_org and git_repo in your project.')
      if git_url =~ /github.com/
        uri = URI(git_url)
        url = "#{uri.scheme}://api.#{uri.host}/repos/#{git_org}/#{git_repo}/pulls"
        begin
          resp = Net::HTTP.get_response(URI.parse(url))
          pulls = JSON.parse(resp.body)
          pulls.map { |p| p['number'] }
        rescue StandardError
          raise 'Failed connecting to GitHub!'
        end
      elsif git_url =~ /bitbucket.org/
        uri = URI.parse("#{git_url}/api/2.0/repositories/#{git_org}/#{git_repo}/pullrequests/")
        begin
          http = Net::HTTP.new(uri.host, uri.port)
          uri.scheme == 'https' ? http.use_ssl = true : nil
          request = Net::HTTP::Get.new(uri.request_uri)
          request.basic_auth(ENV['BITBUCKET_USER'], ENV['BITBUCKET_PASSWORD'])
          response = http.request(request)
          pulls = JSON.parse(response.body)['values']
          pulls.map { |p| {id:p['id'], branch: p['source']['branch']['name']} }
        rescue StandardError
          raise 'Failed connecting to Bitbucket!'
        end
      else
        url = "#{git_url}/api/v3/repos/#{git_org}/#{git_repo}/pulls"
        begin
          resp = Net::HTTP.get_response(URI.parse(url))
          pulls = JSON.parse(resp.body)
          pulls.map { |p| p['number'] }
        rescue StandardError
          raise 'Failed connecting to GitHub Enterprise!'
        end
      end
    end
  end
end
